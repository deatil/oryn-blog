package model

import "core:fmt"

import "oryn:app/db"
import "oryn:app/global"

get_admin :: proc(username: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM commits WHERE username = '%s' LIMIT 1", username)
	item, err := db.get_one(global.conn, query)
	if err != "" {
		return nil
	}

	return item
}

update_admin :: proc(id: string, data: map[string]string) -> bool {
	query := fmt.tprintf(
		"UPDATE %s SET title = '%s' WHERE username = '%s', password = '%s'", 
		table_name("admin"), data["username"], data["password"], id
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
