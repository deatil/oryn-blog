package admin

import "core:fmt"
import "core:time"

import "oryn:http"
import "oryn:jinja"

import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

auth_login :: proc(req: ^http.Request, res: ^http.Response) {
	data := jinja.dict()
	output, _ := view.render("admin/auth/login.html", data)

	http.respond_html(res, output)
}

auth_login_save :: proc(req: ^http.Request, res: ^http.Response) {
	ud: User_Data
	ud.req = req
	ud.res = res

	http.body(req, 5000, &ud, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		ud2 := cast(^User_Data)user_data

		if err != nil {
			http.respond(ud2.res, http.body_error_status(err))
			return
		}

		form, _ := http.body_url_encoded(body)
	
		username := form["username"]
		password := form["password"]

		info := model.get_admin(username)
		if info == nil {
			view.return_error(ud2.res, "login error")
			return
		}

		if !utils.verify_password(password, info["password"]) {
			view.return_error(ud2.res, "login error")
			return
		}

		view.return_success(ud2.res, "login success")
	})
}
