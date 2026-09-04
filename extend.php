<?php

use Flarum\Extend;

return [
    // The flarum-lang/dutch pack ships no fof-gamification.yml, so the voting
    // UI would stay English on an otherwise Dutch forum. Registering a locale
    // directory here fills in the gaps; anything already translated upstream
    // is untouched, and adding a file for another language is just a matter of
    // dropping <code>.yml in locale/.
    (new Extend\Locales(__DIR__.'/locale')),

    // Default sort order for the discussion list.
    //
    // The frontend does not pick a default of its own: with no ?sort= in the
    // URL it looks up sortMap()[''], finds nothing, and sends no sort
    // parameter at all — so whatever this controller defaults to is what the
    // forum opens with. Setting default_route to "/all?sort=hot" does not work,
    // because that is matched as a route path and silently falls back.
    //
    // 'votes' is the raw score: most-upvoted topics first, regardless of age.
    // Swap for ['hotness' => 'desc'] for Gamification's Trending order, which
    // decays the score by age, or ['lastPostedAt' => 'desc'] for Flarum's
    // stock behaviour.
    //
    // lastPostedAt is a tiebreaker, and it is not optional. On a forum where
    // nothing has been voted on yet every row ties at votes = 0, and a single
    // ORDER BY leaves the rest to the database — which returns rows in
    // whatever order it likes, usually close enough to insertion order to look
    // exactly like the default sort had never been changed.
    (new Extend\ApiController(Flarum\Api\Controller\ListDiscussionsController::class))
        ->setSort(['votes' => 'desc', 'lastPostedAt' => 'desc']),
];
