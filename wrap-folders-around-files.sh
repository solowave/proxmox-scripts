#!/bin/bash

# Directory containing the movies
MOVIE_DIR="/path/to/your/movies"

# Iterate through all files in the directory
for file in "$MOVIE_DIR"/*; do
    # Only process files, skip directories
    if [[ -f "$file" ]]; then
        # Get the filename without the extension
        filename=$(basename "$file")
        # Get the name without extension
        name="${filename%.*}"

        # Create a directory with the same name as the file
        mkdir -p "$MOVIE_DIR/$name"

        # Move the file into the newly created directory
        mv "$file" "$MOVIE_DIR/$name"
    fi
done
