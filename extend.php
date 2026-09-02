<?php

use Flarum\Extend;

return [
    // The flarum-lang/dutch pack ships no fof-gamification.yml, so the voting
    // UI would stay English on an otherwise Dutch forum. Registering a locale
    // directory here fills in the gaps; anything already translated upstream
    // is untouched, and adding a file for another language is just a matter of
    // dropping <code>.yml in locale/.
    (new Extend\Locales(__DIR__.'/locale')),
];
