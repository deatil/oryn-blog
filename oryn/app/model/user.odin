package model

import "core:fmt"
import "core:strings"

import "oryn:app/db"
import "oryn:app/global"

get_user :: proc(username: string) -> map[string]string {
	query := fmt.tprintf(
		"SELECT * FROM %s WHERE username = '%s' LIMIT 1", 
		table_name("user"), username
	)
	item, err := db.get_one(global.conn, query)
	if err != "" {
		return nil
	}

	return item
}

update_user :: proc(id: string, data: map[string]string) -> bool {
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

	query := fmt.tprintf(
		"UPDATE %s SET %s WHERE id = '%s'", 
		table_name("user"), strings.to_string(sb), id
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
