#!/bin/bash

# Prompt for the movie directory
read -p "Please enter the full path to the directory containing your movies: " MOVIE_DIR

# Verify the directory exists
if [[ ! -d "$MOVIE_DIR" ]]; then
    echo "Directory does not exist. Please check the path and try again."
    exit 1
fi

# Confirm before proceeding
echo "You have entered: $MOVIE_DIR"
read -p "Do you want to proceed with creating directories and moving files? (y/n): " confirmation

if [[ "$confirmation" != "y" ]]; then
    echo "Operation canceled."
    exit 0
fi

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
        echo "Moved $filename to $name/"
    fi
done

echo "Operation completed."
