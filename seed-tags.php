<?php
/*
 * Creates the forum's primary tags — what Flarum shows as categories — from a
 * JSON file, so the category list is part of the image rather than something
 * you click together after every fresh install.
 *
 * Only ever inserts. A slug that already exists is left exactly as it is, so
 * renaming or recolouring a category in the admin panel survives a restart,
 * and running this twice changes nothing the second time.
 *
 * Usage: php seed-tags.php [path/to/tags.json]
 */

$file = $argv[1] ?? getenv('SEED_TAGS_FILE') ?: __DIR__.'/tags.json';

if (!is_readable($file)) {
    fwrite(STDERR, "seed-tags: no readable tag file at $file\n");
    exit(0); // nothing to seed is not an error
}

$tags = json_decode(file_get_contents($file), true);

if (!is_array($tags)) {
    fwrite(STDERR, "seed-tags: $file is not valid JSON\n");
    exit(1);
}

$prefix = getenv('DB_PREFIX') ?: '';
$table  = $prefix.'tags';

$dsn = sprintf(
    'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
    getenv('DB_HOST') ?: 'db',
    (int) (getenv('DB_PORT') ?: 3306),
    getenv('DB_NAME') ?: 'flarum'
);

$pdo = new PDO($dsn, getenv('DB_USER') ?: 'flarum', getenv('DB_PASS') ?: '', [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
]);

// Append after whatever primary tags already exist, so seeding never reorders
// or collides with categories that are already there.
$nextPosition = (int) $pdo->query("SELECT COALESCE(MAX(position), -1) + 1 FROM `$table`")->fetchColumn();

$exists = $pdo->prepare("SELECT COUNT(*) FROM `$table` WHERE slug = ?");
$insert = $pdo->prepare(
    "INSERT INTO `$table` (name, slug, description, color, icon, position, is_restricted, is_hidden)
     VALUES (:name, :slug, :description, :color, :icon, :position, 0, 0)"
);

$created = 0;
$skipped = 0;

foreach ($tags as $tag) {
    if (empty($tag['name']) || empty($tag['slug'])) {
        fwrite(STDERR, "seed-tags: skipping entry without a name or slug\n");
        continue;
    }

    $exists->execute([$tag['slug']]);

    if ($exists->fetchColumn() > 0) {
        $skipped++;
        continue;
    }

    $insert->execute([
        ':name'        => $tag['name'],
        ':slug'        => $tag['slug'],
        ':description' => $tag['description'] ?? '',
        ':color'       => $tag['color'] ?? '',
        ':icon'        => $tag['icon'] ?? null,
        // position is what makes a tag primary; a null position means secondary.
        ':position'    => $nextPosition++,
    ]);

    $created++;
    echo "  + $tag[name]\n";
}

echo "seed-tags: $created created, $skipped already present\n";
