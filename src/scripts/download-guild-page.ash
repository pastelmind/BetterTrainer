string PAGE_URL = "guild.php?place=trainer";
buffer trainer_page = visit_url(PAGE_URL);

// Dummy map used to save the page as text file
string [string] dummy_map = {
  PAGE_URL: trainer_page,
};

string FILE_NAME = "result.txt";
if (map_to_file(dummy_map, FILE_NAME)) {
  print(PAGE_URL + " saved to " + FILE_NAME);
} else {
  abort("Failed to write to " + FILE_NAME);
}
