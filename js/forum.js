/*
 * Makes the sort dropdown agree with the backend's default sort.
 *
 * The list is ordered by ListDiscussionsController's default (extend.php), but
 * the dropdown never sees that. With no ?sort= in the URL it falls back to the
 * first key of its own sortMap, for both the label and the checkmark:
 *
 *     label:  labels[app.search.params().sort] || Object.values(labels)[0]
 *     active: (app.search.params().sort || Object.keys(map)[0]) === key
 *
 * So the list came back sorted by votes while the control read "Latest".
 * Moving the preferred key to the front of that map lines the two up, with no
 * URL rewriting and no extra request.
 *
 * Plain ES5: Flarum concatenates this into the forum bundle and this repo has
 * no frontend build step.
 */

// Flarum emits "var module={};" before this file and
// "flarum.extensions['site-custom']=module.exports;" after it. Leave exports
// unset and it registers undefined as an extension, which makes bootExtensions
// throw and takes down the whole frontend — not just this tweak.
module.exports = {};

;(function () {
    var compat = typeof flarum !== 'undefined' && flarum.core && flarum.core.compat;
    if (!compat) return;

    // The compat registry hands back the value directly — compat['forum/app']
    // IS the app object, and DiscussionListState IS the class. Webpack builds
    // get a ".default" interop wrapper for free; hand-written code does not, so
    // accept either shape rather than assuming one.
    var extendModule = compat['common/extend'];
    var appEntry = compat['forum/app'];
    var stateEntry = compat['forum/states/DiscussionListState'];

    var app = appEntry && (appEntry.default || appEntry);
    var DiscussionListState = stateEntry && (stateEntry.default || stateEntry);

    if (!app || !app.initializers || !extendModule || !extendModule.extend) return;
    if (!DiscussionListState || !DiscussionListState.prototype) return;

    // Keep in step with setSort() in extend.php.
    var PREFERRED = 'votes';

    function promotePreferred(map) {
        // fof/gamification contributes this key. If it is absent there is
        // nothing to promote, and the stock order is the honest one.
        if (!map || typeof map[PREFERRED] === 'undefined') return;

        var original = {};
        Object.keys(map).forEach(function (key) {
            original[key] = map[key];
            delete map[key];
        });

        // 'relevance' only appears while searching, where it is the correct
        // default and must stay first.
        if (typeof original.relevance !== 'undefined') {
            map.relevance = original.relevance;
            delete original.relevance;
        }

        map[PREFERRED] = original[PREFERRED];
        delete original[PREFERRED];

        Object.keys(original).forEach(function (key) {
            map[key] = original[key];
        });
    }

    // Negative priority so this registers after fof/gamification's initializer:
    // ItemList sorts descending on priority, extend() wrappers run in
    // registration order, and gamification adds the key we reorder. Register
    // at module load instead and it appends votes again after we have moved it.
    app.initializers.add('site-default-sort', function () {
        extendModule.extend(DiscussionListState.prototype, 'sortMap', promotePreferred);
    }, -100);
})();
