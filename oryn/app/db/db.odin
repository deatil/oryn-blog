package db

import "core:c"
import "core:fmt"

import "oryn:mysql"
import "oryn:app/config"

init :: proc() -> (^mysql.MySQL) {
	conn := mysql.init()

	if mysql.connect(
		conn, 
		cstring(raw_data(config.DB_Host)), 
		cstring(raw_data(config.DB_User)), 
		cstring(raw_data(config.DB_Passwd)), 
		cstring(raw_data(config.DB_DB)), 
		c.uint(config.DB_Port),
	) == nil {
		panic(string(mysql.error(conn)))
	}

	if mysql.set_character_set(conn, cstring(raw_data(config.DB_CS_Name))) < 0 {
		panic(string(mysql.error(conn)))
	}

	status := mysql.ping(conn)
	if status != 0 {
		panic(string(mysql.error(conn)))
	}

	return conn
}

close :: proc(conn: ^mysql.MySQL) {
	mysql.close(conn)
}

get_rows :: proc(conn: ^mysql.MySQL, query: string) -> (res: []map[string]string, errstr: string) {
	if mysql.query(conn, cstring(raw_data(query)), c.ulong(len(query))) < 0 {
		return nil, string(mysql.error(conn))
	}

	rs := mysql.store_result(conn)

	rows := mysql.num_rows(rs)
	field_num := mysql.num_fields(rs)
	fields := mysql.fetch_fields(rs)

	items := make([]map[string]string, int(rows))

	for i := 0; i < int(rows); i += 1 {
		row := mysql.fetch_row(rs)

		new_item := make(map[string]string)
		for j := 0; j < int(field_num); j += 1 {
			key_v := fmt.tprintf("%v", fields[j].name)
			new_item[key_v] = fmt.tprintf("%v", row[j])
		}

		items[i] = new_item
	}

	mysql.free_result(rs)

	return items, ""
}

get_one :: proc(conn: ^mysql.MySQL, query: string) -> (res: map[string]string, errstr: string) {
	if mysql.query(conn, cstring(raw_data(query)), c.ulong(len(query))) < 0 {
		return nil, string(mysql.error(conn))
	}

	rs := mysql.store_result(conn)

	rows := mysql.num_rows(rs)
	if rows < 1 {
		return nil, ""
	}

	field_num := mysql.num_fields(rs)
	fields := mysql.fetch_fields(rs)

	row := mysql.fetch_row(rs)

	item := make(map[string]string)
	for i := 0; i < int(field_num); i += 1 {
		key_v := fmt.tprintf("%v", fields[i].name)
		item[key_v] = fmt.tprintf("%v", row[i])
	}

	mysql.free_result(rs)

	return item, ""
}

query :: proc(conn: ^mysql.MySQL, query: string) -> (res: i64, errstr: string) {
	if mysql.query(conn, cstring(raw_data(query)), c.ulong(len(query))) < 0 {
		return 0, string(mysql.error(conn))
	}

	affected_rows_len := mysql.affected_rows(conn)
	return i64(affected_rows_len), ""
}
