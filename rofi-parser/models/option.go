package models

type Option struct {
	Label               IconicMessage `json:"label"`
	Command             string        `json:"command"`
	RequireConfirmation bool          `json:"require_confirmation,omitempty"`
	PreCommands         []string      `json:"pre_commands,omitempty"`
}
