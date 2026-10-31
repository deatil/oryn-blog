# Host: localhost  (Version: 5.7.44)
# Date: 2026-11-01 00:22:44
# Generator: MySQL-Front 5.3  (Build 4.234)

/*!40101 SET NAMES utf8 */;

#
# Structure for table "oryn_admin"
#

DROP TABLE IF EXISTS `oryn_admin`;
CREATE TABLE `oryn_admin` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '账号，大小写字母数字',
  `password` varchar(100) CHARACTER SET utf8mb4 NOT NULL DEFAULT '' COMMENT '密码',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='管理员';

#
# Data for table "oryn_admin"
#

/*!40000 ALTER TABLE `oryn_admin` DISABLE KEYS */;
INSERT INTO `oryn_admin` VALUES (1,'admin','$argon2id$v=19$m=19456,t=2,p=1$yRzfKjab7RTceBaEoSeJyw$FMNCN4mof9qhWOqmhCz9lpJ1iDhylgFlRAXDsj2Yd/s',1793256082);
/*!40000 ALTER TABLE `oryn_admin` ENABLE KEYS */;

#
# Structure for table "oryn_art"
#

DROP TABLE IF EXISTS `oryn_art`;
CREATE TABLE `oryn_art` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `cate_id` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '分类ID',
  `user_id` int(10) unsigned NOT NULL DEFAULT '0' COMMENT '作者',
  `title` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标题',
  `keywords` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '关键字',
  `description` varchar(200) CHARACTER SET utf8mb4 DEFAULT '' COMMENT '描述',
  `content` longtext COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '内容',
  `tags` varchar(250) CHARACTER SET utf8mb4 DEFAULT '' COMMENT '标签',
  `from` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '来源',
  `views` bigint(20) unsigned DEFAULT '1' COMMENT '阅读量',
  `is_top` tinyint(1) unsigned DEFAULT '0' COMMENT '1-置顶',
  `status` tinyint(1) DEFAULT '1' COMMENT '1-启用，0-禁用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=18 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='文章';

#
# Data for table "oryn_art"
#

/*!40000 ALTER TABLE `oryn_art` DISABLE KEYS */;
INSERT INTO `oryn_art` VALUES (2,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1655300840,'127.0.0.1'),(3,1,2,'测试','据说今天下雨','据说今天下雨','<p>测试文章</p>','测试文章','网络',4,0,1,1655823356,'127.0.0.1'),(4,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1655560040,'127.0.0.1'),(5,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1655387240,'127.0.0.1'),(7,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',8,0,1,1655646440,'127.0.0.1'),(8,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',12011206,0,1,1656164840,'127.0.0.1'),(9,1,1,'据说今天下雨，有明星没带伞被雨淋了','下雨,明星','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','明星,下雨,搞笑','网络',54,0,1,1656596840,'127.0.0.1'),(11,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',11,0,1,1655560040,'127.0.0.1'),(12,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','美女','网络',18,0,1,1655560040,'127.0.0.1'),(13,1,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',9,0,1,1655560040,'127.0.0.1'),(14,6,1,'据说今天下雨，有明星没带伞被雨淋了','据说今天下雨','据说今天下雨，有明星没带伞被雨淋了','<p>据说今天下雨，有明星没带伞被雨淋了123</p><p><img src=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" alt=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" data-href=\"/upload/images/78a1b859e4ce392cd5e8fa430382f90a.jpg\" style=\"\"/></p>','八卦,娱乐','网络',25,0,1,1655560040,'127.0.0.1'),(15,1,1,'测试测试123','测试测试123','测试测试123','<p>测试测试123</p>','测试','管理员',5,0,1,1655912049,'127.0.0.1'),(16,1,1,'娱乐圈真的是个圈啊','娱乐圈真的是个圈啊','娱乐圈真的是个圈啊','<p>娱乐圈真的是个圈啊</p>','娱乐圈','管理员',9,1,1,1656170725,'127.0.0.1');
/*!40000 ALTER TABLE `oryn_art` ENABLE KEYS */;

#
# Structure for table "oryn_cate"
#

DROP TABLE IF EXISTS `oryn_cate`;
CREATE TABLE `oryn_cate` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '名称',
  `slug` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标志',
  `desc` varchar(200) CHARACTER SET utf8mb4 DEFAULT '' COMMENT '描述',
  `sort` int(5) DEFAULT '100' COMMENT '排序',
  `status` tinyint(1) DEFAULT '1' COMMENT '1-启用，0-禁用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='分类';

#
# Data for table "oryn_cate"
#

/*!40000 ALTER TABLE `oryn_cate` DISABLE KEYS */;
INSERT INTO `oryn_cate` VALUES (1,'热门八卦','rmbg','热门八卦热门八卦',100,1,1655823356,'127.0.0.1'),(6,'影视综合','video','影视综合',100,1,1655823356,'127.0.0.1'),(9,'诗词江湖','scjh','诗词江湖111',95,1,1655823356,'127.0.0.1');
/*!40000 ALTER TABLE `oryn_cate` ENABLE KEYS */;

#
# Structure for table "oryn_setting"
#

DROP TABLE IF EXISTS `oryn_setting`;
CREATE TABLE `oryn_setting` (
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '字段',
  `value` text COLLATE utf8mb4_unicode_ci COMMENT '字段值',
  `remark` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '字段说明',
  PRIMARY KEY (`name`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='配置';

#
# Data for table "oryn_setting"
#

/*!40000 ALTER TABLE `oryn_setting` DISABLE KEYS */;
INSERT INTO `oryn_setting` VALUES ('website_beian','','网站备案'),('website_copyright','zig-say','版权'),('website_description','zig-say 是使用 httpz, myzql 及 zmpl 的 zig 简易匿名社区系统','网站描述'),('website_keywords','zig-say,社区,社区论坛,简易论坛','网站关键字'),('website_name','zig-say','网站名称'),('website_stat','','统计代码'),('website_status','1','网站关闭状态'),('website_url','http://www.domain.com','网站链接');
/*!40000 ALTER TABLE `oryn_setting` ENABLE KEYS */;
