package model

import "core:fmt"
import "core:strings"

import "oryn:app/db"
import "oryn:app/global"

Cate_Where :: struct {
	offset:  int,
	limit:   int,
	status:  int,
	orderby: string,
}

get_cates :: proc(cfg: Cate_Where) -> []map[string]string {
	offset := cfg.offset
	if offset <= 0 {
		offset = 0
	}
	limit := cfg.limit
	if limit <= 0 {
		limit = 10
	}
	status := cfg.status
	if status != 0 && status != 1 {
		status = 1
	}
	orderby := cfg.orderby
	if orderby == "" {
		orderby = "add_time"
	}

	query := fmt.tprintf(
		`SELECT * FROM %s 
		WHERE status = '%s'
		ORDER BY %s 
		LIMIT %d, %d`, 
		table_name("cate"), status,
		orderby, offset, limit
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_cate :: proc(id: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE id = '%s' LIMIT 1", table_name("cate"), id)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_cate_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM %s LIMIT 1", table_name("cate"))
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

update_cate :: proc(id: string, data: map[string]string) -> bool {
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
		table_name("cate"), strings.to_string(sb), id
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_cate :: proc(id: string) -> bool {
	query := fmt.tprintf("DELETE FROM %s WHERE id = '%s'", table_name("cate"), id)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

add_cate :: proc(data: map[string]string) -> bool {
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
		table_name("cate"), strings.to_string(sb)
	)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}
