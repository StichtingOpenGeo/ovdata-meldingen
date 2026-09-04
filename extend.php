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
    // 'hotness' is FoF Gamification's Trending order: vote score decayed by
    // age, so a well-voted topic leads without pinning the front page forever.
    // Swap for ['votes' => 'desc'] for raw score, or ['lastPostedAt' => 'desc']
    // for Flarum's stock behaviour.
    (new Extend\ApiController(Flarum\Api\Controller\ListDiscussionsController::class))
        ->setSort(['hotness' => 'desc']),
];
