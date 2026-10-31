package model

import "core:fmt"
import "core:strings"

import "oryn:app/db"
import "oryn:app/global"

Art_Where :: struct {
	offset:   int,
	limit:    int,
	keywords: string,
	status:   int,
	orderby:  string,
}

get_arts :: proc(cfg: Art_Where) -> []map[string]string {
	offset := cfg.offset
	if offset <= 0 {
		offset = 0
	}
	limit := cfg.limit
	if limit <= 0 {
		limit = 10
	}
	status := ""
	if cfg.status == 0 || cfg.status == 1 {
		status = fmt.tprintf("AND status = '%s'", cfg.status)
	}
	orderby := cfg.orderby
	if orderby == "" {
		orderby = "a.add_time"
	}

	query := fmt.tprintf(
		`SELECT t.*, u.username, c.name as cate_name
		FROM %s a
		LEFT JOIN %s c ON c.id = a.cate_id
		LEFT JOIN %s u ON u.id = a.user_id
		WHERE a.title LIKE '%%s%' %s
		ORDER BY %s 
		LIMIT %d, %d`, 
		table_name("art"), table_name("cate"), table_name("admin"),
		cfg.keywords, status,
		orderby, offset, limit
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_art :: proc(id: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE id = '%s' LIMIT 1", table_name("art"), id)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_art_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM %s LIMIT 1", table_name("art"))
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

update_art :: proc(id: string, data: map[string]string) -> bool {
	sb := strings.builder_make()
	i: int = 0
	for k, v in data {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}

		strings.write_string(&sb, k)
		strings.write_string(&sb, " = ")
		strings.write_string(&sb, v)

		i += 1
	}

	query := fmt.tprintf(
		`UPDATE %s SET %s WHERE id = '%s'`, 
		table_name("art"), strings.to_string(sb), id
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_art :: proc(id: string) -> bool {
	query := fmt.tprintf("DELETE FROM %s WHERE id = '%s'", table_name("art"), id)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

add_art :: proc(data: map[string]string) -> bool {
	sb := strings.builder_make()
	i: int = 0
	for k, v in data {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}

		strings.write_string(&sb, k)
		strings.write_string(&sb, " = ")
		strings.write_string(&sb, v)

		i += 1
	}

	query := fmt.tprintf(
		`INSERT INTO %s SET %s`, 
		table_name("art"), strings.to_string(sb)
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
