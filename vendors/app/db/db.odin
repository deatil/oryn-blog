package db

import "core:c"
import "vendors:mysql"
import "vendors:app/config"

init :: proc() -> (^mysql.MySQL) {
	conn := mysql.init()

	if mysql.connect(conn, cstring(raw_data(config.Mysql_Host)), cstring(raw_data(config.Mysql_User)), cstring(raw_data(config.Mysql_Passwd)), cstring(raw_data(config.Mysql_DB)), c.uint(config.Mysql_Port)) == nil {
		panic(string(mysql.error(conn)))
	}

	if mysql.set_character_set(conn, cstring(raw_data(config.Mysql_CS_Name))) < 0 {
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
	nfs := mysql.num_fields(rs)
	fields := mysql.fetch_fields(rs)

	items := make([]map[string]string, int(rows))

	for i := 0; i < int(rows); i += 1 {
		row := mysql.fetch_row(rs)

		new_item := make(map[string]string)
		for j := 0; j < int(nfs); j += 1 {
			new_item[string(fields[j].name)] = string(row[j])
		}

		items[i] = new_item
	}

	mysql.free_result(rs)

	return items, ""
}

get_one :: proc(conn: ^mysql.MySQL, query: string) -> (res: map[string]string, errstr: string) {
	items, err := get_rows(conn, query)
	if len(err) > 0 {
		return nil, err
	}

	if len(items) > 0 {
		return items[0], ""
	}

	return nil, ""
}

query :: proc(conn: ^mysql.MySQL, query: string) -> (res: i64, errstr: string) {
	if mysql.query(conn, cstring(raw_data(query)), c.ulong(len(query))) < 0 {
		return 0, string(mysql.error(conn))
	}

	affected_rows_len := mysql.affected_rows(conn)
	return i64(affected_rows_len), ""
}
