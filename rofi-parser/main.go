package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"menglishca/rofi-suite/models"
	"os"
	"os/exec"
	"strings"
)

func main() {
	configPointer := flag.String("config", "", "Path to the user's configuration file")
	dataDirectoryPointer := flag.String("data", "", "Path to the rofi suite data directory")
	flag.Parse()

	userArguments := flag.Args()

	if *configPointer == "" || *dataDirectoryPointer == "" {
		fmt.Println("Error: Both --config and --data flags are required.")
		flag.Usage()
		return
	}

	if len(userArguments) != 1 {
		fmt.Println("Error: Exactly one menu name must be provided as an argument.")
		flag.Usage()
		return
	}

	menuName := userArguments[0]

	configFileBytes, err := os.ReadFile(*configPointer)
	if err != nil {
		fmt.Println("Error reading config file:", err)
		return
	}

	var userConfig models.UserConfig
	err = json.Unmarshal(configFileBytes, &userConfig)
	if err != nil {
		fmt.Println("Error parsing config file:", err)
		return
	}

	chosenMenu, exists := userConfig.Menus[menuName]
	if !exists {
		fmt.Println("Error: Menu name not found in configuration:", menuName)
		return
	}

	validationError := chosenMenu.Validate()
	if validationError != nil {
		fmt.Println("Error validating menu:", validationError)
		return
	}

	// rofiCmd, err := chosenMenu.GetRofiCmd(*dataDirectoryPointer)
	// if err != nil {
	// 	fmt.Println("Error preparing rofi command:", err)
	// 	return
	// }

	// rofiCmd.Stdout = os.Stdout
	// rofiCmd.Stderr = os.Stderr

	// err = rofiCmd.Run()
	// if err != nil {
	// 	fmt.Println("Error running rofi command:", err)
	// 	return
	// }

	fmt.Println(chosenMenu.GetRofiCommandString(*dataDirectoryPointer))

}

func evalShellString(input string) string {
	cmdStr := input[2 : len(input)-1]
	cmd := exec.Command("bash", "-c", cmdStr)

	var out bytes.Buffer
	cmd.Stdout = &out
	err := cmd.Run()

	if err != nil {
		return "Error" // Fallback if the amixer command fails
	}
	return strings.TrimSpace(out.String())
}
