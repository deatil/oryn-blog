package model

import "core:fmt"

import "vendors:app/db"

get_commit_all :: proc(offset: int = 0) -> []map[string]string {
	conn := db.init()

	query := fmt.tprintf("SELECT * FROM commits ORDER BY id LIMIT %d, 10", offset)
	items, _ := db.get_rows(conn, query)

	return items
}

get_commit_one :: proc(id: string) -> map[string]string {
	conn := db.init()

	query := fmt.tprintf("SELECT * FROM commits WHERE id = '%s' LIMIT 1", id)
	item, _ := db.get_one(conn, query)

	return item
}

get_commit_count :: proc() -> string {
	conn := db.init()

	query := fmt.tprintf("SELECT * FROM commits count(id) as n LIMIT 1")
	item, _ := db.get_one(conn, query)

	return item["n"]
}

update_commit :: proc(id: string, data: map[string]string) -> bool {
	conn := db.init()

	query := fmt.tprintf("UPDATE commits SET title = %s, content = %s, add_time = %s WHERE id = %s", data["title"], data["content"], data["add_time"], id)
	_, err := db.query(conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_commit :: proc(id: string) -> bool {
	conn := db.init()

	query := fmt.tprintf("DELETE FROM commits WHERE id = %s", id)
	_, err := db.query(conn, query)
	if err != "" {
		return false
	}

	return true
}

add_commit :: proc(data: map[string]string) -> bool {
	conn := db.init()

	query := fmt.tprintf("INSERT INTO commits (title, content, add_time) VALUES (%s, %s, %s)", data["title"], data["content"], data["add_time"])
	_, err := db.query(conn, query)
	if err != "" {
		return false
	}

	return true
}
