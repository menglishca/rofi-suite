package models

type UserConfig struct {
	Menus map[string]Menu `json:"menus"`
}
