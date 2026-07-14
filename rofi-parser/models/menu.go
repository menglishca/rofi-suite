package models

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

type Menu struct {
	Prompt       IconicMessage `json:"prompt,omitempty"`
	MenuType     string        `json:"type"`
	Theme        string        `json:"theme"`
	Color        string        `json:"color"`
	Message      string        `json:"message,omitempty"`
	Options      []Option      `json:"options,omitempty"`
	Confirmation *Confimration `json:"confirmation,omitempty"`
	Action       string        `json:"action,omitempty"`
}

func (menu Menu) Validate() error {
	if menu.Confirmation != nil && *menu.Confirmation == (Confimration{}) {
		return fmt.Errorf("confirmation settings are invalid")
	}

	if (menu.MenuType == "launcher" || menu.MenuType == "dmenu") && menu.Action != "" {
		return fmt.Errorf("menu type %s cannot have an action", menu.MenuType)
	}

	if menu.Theme == "" {
		return fmt.Errorf("menu type %s requires a theme", menu.MenuType)
	}

	if menu.Color == "" {
		return fmt.Errorf("menu type %s requires a color", menu.MenuType)
	}

	hasConfirmation := menu.Confirmation != nil

	switch menu.MenuType {
	case "launcher":
		if len(menu.Options) != 0 {
			return fmt.Errorf("launcher menu do not support options")
		}
		if menu.Prompt != (IconicMessage{}) {
			return fmt.Errorf("launcher menu do not support prompts")
		}
	default:
		if len(menu.Options) == 0 {
			return fmt.Errorf("menu type %s requires at least one option", menu.MenuType)
		}
		if menu.Prompt == (IconicMessage{}) {
			return fmt.Errorf("menu type %s requires a prompt", menu.MenuType)
		}

		requiresConfirmation := slices.ContainsFunc(menu.Options, func(option Option) bool {
			return option.RequireConfirmation
		})

		if requiresConfirmation && !hasConfirmation {
			return fmt.Errorf("menu type %s has options that require confirmation, but no confirmation settings are provided", menu.MenuType)
		}
	}
	return nil
}

func (menu Menu) GetActionArguments() []string {
	if menu.Action != "" {
		return []string{"-show", menu.Action}
	}

	return []string{"-dmenu"}
}

func (menu Menu) GetThemeArgs(dataDirectory string) ([]string, error) {
	themePath, err := menu.getThemeRasiPath(dataDirectory)
	if err != nil {
		return nil, err
	}
	colorPath, err := menu.getTargetColorsPath(dataDirectory)
	if err != nil {
		return nil, err
	}

	return []string{
		"-theme-str", fmt.Sprintf("@import \"%s\"", themePath),
		"-theme-str", fmt.Sprintf("@import \"%s\"", colorPath),
	}, nil
}

func (menu Menu) GetMenuArguments(dataDirectory string) ([]string, error) {
	themeArgs, err := menu.GetThemeArgs(dataDirectory)
	if err != nil {
		return nil, err
	}

	var menuArguments []string
	menuArguments = append(menuArguments, themeArgs...)
	menuArguments = append(menuArguments, menu.GetActionArguments()...)
	menuArguments = append(menuArguments, "-p", menu.Prompt.String())

	if menu.MenuType == "dmenu" {
		menuArguments = append(menuArguments, "-format", "i")
	}

	if menu.Message != "" {
		menuArguments = append(menuArguments, "-mesg", menu.Message)
	}
	return menuArguments, nil
}

func (menu Menu) GetDMenuString() string {
	var dmenuStringBuilder strings.Builder

	for _, option := range menu.Options {
		dmenuStringBuilder.WriteString(option.Label.String())
		dmenuStringBuilder.WriteString("\n")
	}

	return dmenuStringBuilder.String()
}

func (menu Menu) GetRofiCommandString(dataDirectory string) (string, error) {
	menuArguments, err := menu.GetMenuArguments(dataDirectory)
	if err != nil {
		return "", err
	}

	var dmenuString string
	if menu.MenuType == "dmenu" {
		dmenuString = menu.GetDMenuString()
	}

	return fmt.Sprintf("rofiInput=$'%s'; echo \"$rofiInput\" |rofi %s", strings.Join(menuArguments, " "), dmenuString), nil
}

func (menu Menu) GetRofiCmd(dataDirectory string) (*exec.Cmd, error) {
	menuArguments, err := menu.GetMenuArguments(dataDirectory)
	if err != nil {
		return nil, err
	}

	rofiCommand := exec.Command("rofi", menuArguments...)

	if menu.MenuType == "dmenu" {
		dmenuString := menu.GetDMenuString()
		rofiCommand.Stdin = strings.NewReader(dmenuString)
	}

	return rofiCommand, nil
}

func (menu Menu) getThemeRasiPath(dataDirectory string) (string, error) {
	path := filepath.Join(dataDirectory, "themes", menu.MenuType, menu.Theme+".rasi")
	_, err := os.Stat(path)
	if err != nil {
		path := filepath.Join(dataDirectory, "themes", menu.MenuType, "default.rasi")
		_, err := os.Stat(path)
		if err != nil {
			return "", fmt.Errorf("theme %s not found for menu type %s, and default theme is also missing", menu.Theme, menu.MenuType)
		}
	}

	return filepath.Abs(path)
}

func (menu Menu) getTargetColorsPath(dataDirectory string) (string, error) {
	path := filepath.Join(dataDirectory, "themes", "colors", menu.Color+".rasi")
	_, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("color theme %s not found", menu.Color)
	}

	return filepath.Abs(path)
}
