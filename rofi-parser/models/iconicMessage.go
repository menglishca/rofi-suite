package models

import "fmt"

type IconicMessage struct {
	Message string `json:"message"`
	Icon    string `json:"icon,omitempty"`
}

func (im IconicMessage) String() string {
	if im.Icon == "" {
		return im.Message
	}
	return fmt.Sprintf("%s %s", im.Icon, im.Message)
}
