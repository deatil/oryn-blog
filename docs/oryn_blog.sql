DROP TABLE IF EXISTS `oryn_art`;
CREATE TABLE `oryn_art` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `cate_id` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '分类ID',
  `user_id` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '作者',
  `title` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标题',
  `keywords` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '关键字',
  `description` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '描述',
  `content` longtext CHARACTER SET utf8mb4 COMMENT '内容',
  `tags` varchar(250) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '标签',
  `from` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '来源',
  `views` bigint(20) unsigned DEFAULT '0' COMMENT '阅读量',
  `is_top` tinyint(1) unsigned DEFAULT '0' COMMENT '1-置顶',
  `status` tinyint(1) DEFAULT '1' COMMENT '1-启用，0-禁用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=20 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='文章';

DROP TABLE IF EXISTS `oryn_cate`;
CREATE TABLE `oryn_cate` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '名称',
  `slug` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标志',
  `desc` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '描述',
  `sort` int(5) DEFAULT '100' COMMENT '排序',
  `status` tinyint(1) DEFAULT '1' COMMENT '1-启用，0-禁用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='分类';

DROP TABLE IF EXISTS `oryn_comment`;
CREATE TABLE `oryn_comment` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `art_id` int(10) NOT NULL DEFAULT '0' COMMENT '文章ID',
  `content` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '内容',
  `username` varchar(50) CHARACTER SET utf8mb4 NOT NULL DEFAULT '' COMMENT '账号，大小写字母数字',
  `status` tinyint(3) DEFAULT '0' COMMENT '状态，1-启用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=37 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='评论';

DROP TABLE IF EXISTS `oryn_setting`;
CREATE TABLE `oryn_setting` (
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '字段',
  `value` text COLLATE utf8mb4_unicode_ci COMMENT '字段值',
  `remark` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '字段说明',
  PRIMARY KEY (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='配置';

DROP TABLE IF EXISTS `oryn_user`;
CREATE TABLE `oryn_user` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '账号，大小写字母数字',
  `password` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '密码',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='管理员';

INSERT INTO `oryn_art` VALUES (2,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1795426589,'127.0.0.1'),(3,1,2,'测试','据说今天下雨','据说今天下雨','<p>测试文章</p>','测试文章','网络',4,0,1,1795426589,'127.0.0.1'),(4,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1795426589,'127.0.0.1'),(5,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1795426589,'127.0.0.1'),(7,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1795426589,'127.0.0.1'),(8,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',12011206,0,1,1795426589,'127.0.0.1'),(9,6,1,'据说今天下雨，有明星没带伞被雨淋了1','下雨,明星1','据说今天下雨，有明星没带伞被雨淋了1','<p>据说今天下雨，有明星没带伞被雨淋了</p>','明星,下雨,搞笑','网络1',55,0,1,1795426589,'127.0.0.1'),(11,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',11,0,1,1795426589,'127.0.0.1'),(12,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','美女','网络',18,0,1,1795426589,'127.0.0.1'),(13,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',9,0,1,1795426589,'127.0.0.1'),(14,6,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了123</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',25,0,1,1795426589,'127.0.0.1'),(15,1,1,'测试测试123','测试测试123','测试测试123','<p>测试测试123</p>','测试','管理员',5,0,1,1795426589,'127.0.0.1'),(16,1,1,'娱乐圈真的是个圈啊','娱乐圈真的是个圈啊','娱乐圈真的是个圈啊','<p>娱乐圈真的是个圈啊</p>','娱乐圈','管理员',9,1,1,1795426589,'127.0.0.1'),(19,1,1,'据说AI发展得很好','ai','据说AI发展得很好','<p>据说AI发展得很好</p>','','',1,0,1,1795426908,'127.0.0.1');
INSERT INTO `oryn_cate` VALUES (1,'热门八卦','rmbg','热门八卦热门八卦',100,1,1795426589,'127.0.0.1'),(6,'影视综合','video','影视综合',100,1,1795426589,'127.0.0.1'),(9,'诗词江湖','scjh','诗词江湖111',95,1,1795426589,'127.0.0.1'),(16,'特色1','test2','',100,1,1795426589,'127.0.0.1'),(17,'test23','test23','55',100,1,1795426589,'127.0.0.1');
INSERT INTO `oryn_comment` VALUES (1,19,'测试','yy',1,1795427274,'127.0.0.1');
INSERT INTO `oryn_setting` VALUES ('website_beian','','网站备案'),('website_copyright','oryn-blog','版权'),('website_description','oryn-blog 是使用 gjallarhorn, odin-mysql 及 jinja 的 oryn-blog 博客系统','网站描述'),('website_keywords','oryn-blog,博客','网站关键字'),('website_name','oryn-blog','网站名称'),('website_stat','','统计代码'),('website_status','1','网站关闭状态'),('website_url','http://www.domain.com','网站链接');
INSERT INTO `oryn_user` VALUES (1,'admin','$argon2id$v=19$m=19456,t=2,p=1$AVdiJJGXZcAcPyT4q+KoUg$UEsYc0L55FHAfUpKtsdVe4VVhICdMj2pwjeww/ksky8',1795426589);
