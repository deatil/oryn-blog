package controller

import "vendors:http"

static :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_dir(res, "/static", "resources/static", req.url_params[0])
}
