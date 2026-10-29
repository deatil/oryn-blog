package model

import "core:fmt"

import "oryn:app/config"

table_name :: proc(name: string) -> string {
	table_string := fmt.tprintf("%s%s", config.Table_Prefix, name)
	return table_string
}
