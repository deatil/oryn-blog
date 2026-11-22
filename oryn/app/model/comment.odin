package model

import "core:fmt"

import "oryn:app/db"
import "oryn:app/global"

Comment_Where :: struct {
	offset:  int,
	limit:   int,
	status:  int,
	wheres:  string,
	orderby: string,
}

get_comments :: proc(cfg: Comment_Where) -> []map[string]string {
	offset := cfg.offset
	if offset <= 0 {
		offset = 0
	}
	limit := cfg.limit
	if limit <= 0 {
		limit = 10
	}
	status := ""
	if cfg.status != -1 {
		status = fmt.tprintf("AND status = %d", cfg.status)
	}
	orderby := cfg.orderby
	if orderby == "" {
		orderby = "add_time DESC"
	}

	query := fmt.tprintf(
		`SELECT * FROM %s 
		WHERE 1 = 1 %s %s
		ORDER BY %s
		LIMIT %d, %d`, 
		table_name("comment"), status, cfg.wheres,
		orderby, offset, limit
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_comment :: proc(id: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE id = '%s' LIMIT 1", table_name("comment"), id)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_comment_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM %s LIMIT 1", table_name("comment"))
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

get_comment_count_where :: proc(cfg: Comment_Where) -> string {
	status := ""
	if cfg.status == 0 || cfg.status == 1 {
		status = fmt.tprintf("AND status = '%s'", cfg.status)
	}

	query := fmt.tprintf(
		"SELECT count(id) as n FROM %s WHERE 1=1 %s %s LIMIT 1", 
		table_name("comment"), status, cfg.wheres
	)
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

update_comment :: proc(id: string, data: map[string]string) -> bool {
	set_str := datas_to_string(data)

	query := fmt.tprintf(
		`UPDATE %s SET %s WHERE id = '%s'`, 
		table_name("comment"), set_str, id
	)
	// fmt.println(query)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_comment :: proc(id: string) -> bool {
	query := fmt.tprintf("DELETE FROM %s WHERE id = '%s'", table_name("comment"), id)
	afr, _ := db.query(global.conn, query)
	if afr > 0 {
		return true
	}

	return false
}

add_comment :: proc(data: map[string]string) -> bool {
	set_str := datas_to_string(data)

	query := fmt.tprintf(
		`INSERT INTO %s SET %s`, 
		table_name("comment"), set_str
	)
	afr, _ := db.query(global.conn, query)
	if afr > 0 {
		return true
	}

	return false
}
