package model

import "core:fmt"

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
	set_str := datas_to_string(data)

	query := fmt.tprintf(
		"UPDATE %s SET %s WHERE id = '%s'", 
		table_name("user"), set_str, id
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
