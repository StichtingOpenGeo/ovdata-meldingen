/*
 * Makes the sort dropdown agree with the backend's default sort.
 *
 * The list is ordered by ListDiscussionsController's default (see extend.php),
 * but the dropdown never sees that. With no ?sort= in the URL it falls back to
 * the first key of its own sortMap for both the label and the checkmark:
 *
 *     label: labels[app.search.params().sort] || Object.values(labels)[0]
 *     active: (app.search.params().sort || Object.keys(map)[0]) === key
 *
 * So the list came back sorted by votes while the control said "Latest".
 * Moving the preferred key to the front of the map lines the two up.
 *
 * Plain ES5 on purpose: Flarum concatenates this file into the forum bundle,
 * there is no build step in this repo, and nothing here needs one.
 */
;(function () {
    if (typeof flarum === 'undefined' || !flarum.core || !flarum.core.compat) return;

    var compat = flarum.core.compat;
    var extendModule = compat['common/extend'];
    var stateModule = compat['forum/states/DiscussionListState'];

    if (!extendModule || !stateModule || !stateModule.default) return;

    // Keep in step with setSort() in extend.php.
    var PREFERRED = 'votes';

    extendModule.extend(stateModule.default.prototype, 'sortMap', function (map) {
        // fof/gamification adds this key; if it has not run yet there is
        // nothing to promote and the stock order is the honest one.
        if (!map || typeof map[PREFERRED] === 'undefined') return;

        var original = {};
        Object.keys(map).forEach(function (key) {
            original[key] = map[key];
            delete map[key];
        });

        // 'relevance' is only present while searching, where it is the correct
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
    });
})();
