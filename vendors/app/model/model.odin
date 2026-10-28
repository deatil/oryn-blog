package model

import "core:fmt"

import "vendors:app/db"
import "vendors:app/global"

get_commit_all :: proc(offset: int = 0) -> []map[string]string {
	query := fmt.tprintf("SELECT * FROM commits ORDER BY id LIMIT %d, 10", offset)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_commit_one :: proc(id: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM commits WHERE id = '%s' LIMIT 1", id)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_commit_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM commits LIMIT 1")
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

update_commit :: proc(id: string, data: map[string]string) -> bool {
	query := fmt.tprintf("UPDATE commits SET title = '%s', content = '%s', add_time = %s WHERE id = %s", data["title"], data["content"], data["add_time"], id)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_commit :: proc(id: string) -> bool {
	query := fmt.tprintf("DELETE FROM commits WHERE id = %s", id)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

add_commit :: proc(data: map[string]string) -> bool {
	query := fmt.tprintf("INSERT INTO commits (title, content, add_time) VALUES ('%s', '%s', %s)", data["title"], data["content"], data["add_time"])
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
