package model

import "core:fmt"

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
	status := "1 = 1"
	if cfg.status != -1 {
		status = fmt.tprintf("status = %d", cfg.status)
	}
	orderby := cfg.orderby
	if orderby == "" {
		orderby = "add_time DESC"
	}

	query := fmt.tprintf(
		`SELECT * FROM %s 
		WHERE %s ORDER BY %s 
		LIMIT %d, %d`, 
		table_name("cate"), status,
		orderby, offset, limit
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_cate_all :: proc() -> []map[string]string {
	query := fmt.tprintf(
		`SELECT * FROM %s 
		WHERE status = 1 
		ORDER BY add_time DESC`, 
		table_name("cate")
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_cate_all2 :: proc() -> []map[string]string {
	query := fmt.tprintf(
		`SELECT * FROM %s 
		ORDER BY add_time DESC`, 
		table_name("cate")
	)
	items, _ := db.get_rows(global.conn, query)

	return items
}

get_cate :: proc(id: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE id = '%s' LIMIT 1", table_name("cate"), id)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_cate_by_slug :: proc(slug: string) -> map[string]string {
	query := fmt.tprintf("SELECT * FROM %s WHERE slug = '%s' LIMIT 1", table_name("cate"), slug)
	item, _ := db.get_one(global.conn, query)

	return item
}

get_cate_count :: proc() -> string {
	query := fmt.tprintf("SELECT count(id) as n FROM %s LIMIT 1", table_name("cate"))
	item, _ := db.get_one(global.conn, query)

	return item["n"]
}

update_cate :: proc(id: string, data: map[string]string) -> bool {
	set_str := datas_to_string(data)

	query := fmt.tprintf(
		`UPDATE %s SET %s WHERE id = '%s'`, 
		table_name("cate"), set_str, id
	)
	// fmt.println(query)
	_, err := db.query(global.conn, query)
	if err != "" {
		return false
	}

	return true
}

delete_cate :: proc(id: string) -> bool {
	query := fmt.tprintf("DELETE FROM %s WHERE id = '%s'", table_name("cate"), id)
	afr, _ := db.query(global.conn, query)
	if afr > 0 {
		return true
	}

	return false
}

add_cate :: proc(data: map[string]string) -> bool {
	set_str := datas_to_string(data)

	query := fmt.tprintf(
		`INSERT INTO %s SET %s`, 
		table_name("cate"), set_str
	)
	afr, _ := db.query(global.conn, query)
	if afr > 0 {
		return true
	}

	return false
}
