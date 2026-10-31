package model

import "core:fmt"

import "oryn:app/db"
import "oryn:app/global"

get_settings :: proc() -> []map[string]string {
	query := fmt.tprintf(
		`SELECT name, value, remark 
		FROM %s`, 
		table_name("setting")
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_setting_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM %s LIMIT 1", table_name("setting"))
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

get_setting_by_name :: proc(name: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE name = '%s' LIMIT 1", table_name("setting"), name)
	item, _ := db.get_one(global.conn, query)

	return item
}

update_setting :: proc(id: string, name: string, value: string) -> bool {
	query := fmt.tprintf(
		`UPDATE %s SET value = '%s' WHERE name = '%s'`, 
		table_name("setting"), value, name
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
