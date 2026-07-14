package models

import (
	"fmt"
)

type Confimration struct {
	Title     IconicMessage `json:"title"`
	Message   string        `json:"message"`
	YesPrompt string        `json:"yes_prompt"`
	NoPrompt  string        `json:"no_prompt"`
}

func (confirmation *Confimration) GetConfirmationArguments(themeString string) []string {
	if confirmation == nil {
		return []string{}
	}

	confirmationTitle := "Confirmation"
	confirmationMessage := "Are you sure?"

	if confirmation.Title.Message != "" {
		confirmationTitle = confirmation.Title.String()
	}

	if confirmation.Message != "" {
		confirmationMessage = confirmation.Message
	}

	return []string{
		"-theme-str", fmt.Sprintf(
			"%s window {location: center; anchor: center; fullscreen: false; width: 350px;} mainbox {orientation: vertical; children: [ \"message\", \"listview\" ];} listview {columns: 2; lines: 1;} element-text {horizontal-align: 0.5;} textbox {horizontal-align: 0.5;}",
			themeString,
		),
		"-dmenu", "",
		"-p", confirmationTitle,
		"-mesg", confirmationMessage,
	}
}
