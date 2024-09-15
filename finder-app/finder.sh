#!/bin/sh

# Check if the number of arguments is not equal to 2
if [ "$#" -ne 2 ]; then
    echo "Error: Two arguments required - (1) a directory and (2) a search string."
    exit 1
fi

# Assign arguments to variables
filesdir=$1
searchstr=$2

# Check if argument 1 is a valid directory
if [ ! -d "$filesdir" ]; then
    echo "Error: $filesdir is not a valid directory."
    exit 1
fi

# Count the number of files in the directory and subdirectories
num_files=$(find "$filesdir" -type f | wc -l)

# Count the tot number of lines that contain the search string in all the files
num_matching_lines=$(grep -r "$searchstr" "$filesdir" 2>/dev/null | wc -l)

# Print result
echo "The number of files are $num_files and the number of matching lines are $num_matching_lines"