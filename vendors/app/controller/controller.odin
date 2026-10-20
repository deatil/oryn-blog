package controller

import "vendors:http"
import "vendors:app/view"
import "vendors:app/model"

index :: proc(req: ^http.Request, res: ^http.Response) {
	items := model.get_commit_all()

	data_json, _ := view.marshal_json(items)
	data, _ := view.load_json_string(data_json)

	tpl := "resources/view/index.html"
	output, _ := view.render(tpl, data)

	http.respond_html(res, output)
}

view :: proc(req: ^http.Request, res: ^http.Response) {
	id := req.url_params[0]

	item := model.get_commit_one(id)

	data := make(map[string]view.JSON_Data)
	data["title"] = item["title"]
	data["content"] = item["content"]

	tpl := "resources/view/view.html"
	output, _ := view.render(tpl, data)

	http.respond_html(res, output)
}

