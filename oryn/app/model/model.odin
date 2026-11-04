package model

import "core:fmt"
import "core:strings"

import "oryn:app/config"

table_name :: proc(name: string) -> string {
	table_string := fmt.tprintf("%s%s", config.Table_Prefix, name)
	return table_string
}

datas_to_string :: proc(data: map[string]string) -> string {
	sb := strings.builder_make()
	i: int = 0
	for k, v in data {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}

		strings.write_string(&sb, k)
		strings.write_string(&sb, " = '")
		strings.write_string(&sb, v)
		strings.write_string(&sb, "'")

		i += 1
	}

	return strings.to_string(sb)
}
