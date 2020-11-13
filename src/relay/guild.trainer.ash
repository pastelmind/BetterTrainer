// Let's test if KoLmafia loads a separate script for guild.php?place=trainer

print("guild.trainer.ash called!");

// Load the page
buffer page = visit_url();

// Report the URL to the CLI
print("Relay URL: " + get_path_full());

// For now, write the page unchanged
write(page);
