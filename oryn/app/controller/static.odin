package controller

import "oryn:http"

import "oryn:app/config"

static :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_dir(res, "/static", config.Static_Path, req.url_params[0])
}
