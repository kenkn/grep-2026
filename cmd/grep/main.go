package main

import (
	"fmt"
	"os"
	"strings"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Println("Usage: grep <pattern> <file>")
		os.Exit(1)
	}

	// pattern := os.Args[1]
	file := os.Args[2]

	content, err := os.ReadFile(file)
	if err != nil {
		fmt.Println("Error reading file:", err)
		os.Exit(1)
	}

	contentString := string(content)
	lines := strings.Split(contentString, "\n")
	for _, line := range lines {
		pattern := os.Args[1]
		if strings.Contains(line, pattern) {
			fmt.Println(line)
		}
	}
}
