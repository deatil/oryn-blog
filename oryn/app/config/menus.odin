package config

Amin_Menus := `{
	"status": 0,
	"msg": "ok",
	"data": [
		{
			"id": 1,
			"name": "文章管理",
			"icon": "&#xe705;",
			"url": "",
			"children": [{
				"id": 11,
				"name": "文章列表",
				"icon": "",
				"url": "/admin/article/index"
			}, {
				"id": 12,
				"name": "分类管理",
				"icon": "",
				"url": "/admin/article/category"
			}]
		},
		{
			"id": 2,
			"name": "评论管理",
			"icon": "&#xe705;",
			"url": "",
			"children": [{
				"id": 21,
				"name": "评论列表",
				"icon": "",
				"url": "/admin/comment"
			}]
		},
		{
			"id": 3,
			"name": "账号管理",
			"icon": "&#xe726;",
			"url": "",
			"children": [
				{
					"id": 31,
					"name": "账号列表",
					"icon": "",
					"url": "/pages/user"
				}
			]
		}
	]
}`

