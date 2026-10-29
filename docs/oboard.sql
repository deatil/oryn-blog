
#
# Structure for table "commits"
#

DROP TABLE IF EXISTS `commits`;
CREATE TABLE `commits` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `title` varchar(200) CHARACTER SET utf8 DEFAULT '',
  `content` text COLLATE utf8_unicode_ci,
  `add_time` int(10) DEFAULT '0' COMMENT '添加时间',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

#
# Data for table "commits"
#

/*!40000 ALTER TABLE `commits` DISABLE KEYS */;
INSERT INTO `commits` VALUES (1,'kll','klluuuu',1739783728),(2,'kll2','klluuuu',1739783728),(3,'kll36','klluuuu',1793206379),(5,'oo2','yy2',1793255507),(6,'ppp3','oooo3',1793256082);
/*!40000 ALTER TABLE `commits` ENABLE KEYS */;

#
# Structure for table "oryn_admin"
#

DROP TABLE IF EXISTS `oryn_admin`;
CREATE TABLE `oryn_admin` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '账号，大小写字母数字',
  `password` varchar(70) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '密码',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='管理员';

#
# Data for table "oryn_admin"
#

/*!40000 ALTER TABLE `oryn_admin` DISABLE KEYS */;
INSERT INTO `oryn_admin` VALUES (1,'admin','$bcrypt$r=5$Qpw5YcBXSwT5VZqVzTNdBA$XCs/K6s2vYmoHqNcGkJLRXPW7CW+Th8',1793256082);
/*!40000 ALTER TABLE `oryn_admin` ENABLE KEYS */;

#
# Structure for table "oryn_comment"
#

DROP TABLE IF EXISTS `oryn_comment`;
CREATE TABLE `oryn_comment` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) NOT NULL DEFAULT '0' COMMENT '账号ID',
  `topic_id` int(10) NOT NULL DEFAULT '0' COMMENT '话题ID',
  `content` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '内容',
  `status` tinyint(3) DEFAULT '0' COMMENT '状态，1-启用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=37 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='评论';

#
# Data for table "oryn_comment"
#

/*!40000 ALTER TABLE `oryn_comment` DISABLE KEYS */;
INSERT INTO `oryn_comment` VALUES (1,3,3,'testsert1211',1,1739779230,'127.0.0.1'),(2,6,3,'qweqwe',1,1739779230,'0.0.0.0'),(3,6,3,'333rftgd22',1,1739779230,'0.0.0.0'),(4,6,3,'tyuhj',1,1739779230,''),(5,6,3,'tyuhj',1,1739779230,''),(6,6,3,'tyuhj',1,1739779230,''),(8,6,3,'简易论坛8',1,1739779230,'0.0.0.0'),(11,6,3,'tyuhj',1,1739779230,''),(12,6,3,'tyuhj',1,1739779230,''),(13,6,3,'tyuhj',1,1739779230,''),(14,6,3,'tyuhj',1,1739779230,''),(15,6,3,'tyuhj',1,1739779230,''),(16,6,3,'tyuhj',1,1739779230,''),(17,6,3,'tyuhj',1,1739779230,''),(18,6,3,'tyuhj',1,1739779230,''),(19,6,3,'tyuhj',1,1739779230,''),(21,6,3,'tyuhj',1,1739779230,''),(22,6,3,'tyuhj',1,1739779230,''),(23,6,3,'tyuhj',1,1739779230,''),(24,6,3,'tyuhj',1,1739779230,''),(25,6,3,'tyuhj',1,1739779230,''),(26,1,6,'123',1,1739779515,''),(27,1,8,'cesgi2',1,1739786330,'0.0.0.0'),(28,1,8,'123qwew',1,1739786339,''),(29,1,8,'123qwew',1,1739786339,''),(30,4,16,'222',1,1791560874,''),(31,4,8,'33333',1,1791560901,''),(32,4,8,'555',1,1791560920,''),(33,4,17,'123',1,1791560945,''),(34,5,18,'222',1,1791646745,''),(35,7,19,'777',1,1791912333,''),(36,11,19,'66',1,1792085299,'');
/*!40000 ALTER TABLE `oryn_comment` ENABLE KEYS */;

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

#
# Structure for table "oryn_topic"
#

DROP TABLE IF EXISTS `oryn_topic`;
CREATE TABLE `oryn_topic` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(10) NOT NULL DEFAULT '0' COMMENT '账号ID',
  `title` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '密码',
  `content` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '内容',
  `views` int(11) DEFAULT '0' COMMENT '阅读量',
  `status` tinyint(3) DEFAULT '0' COMMENT '状态，1-启用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=21 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='话题';

#
# Data for table "oryn_topic"
#

/*!40000 ALTER TABLE `oryn_topic` DISABLE KEYS */;
INSERT INTO `oryn_topic` VALUES (3,3,'zig 为什么老是返回的字符不是自己期望的数据','zig 为什么老是返回的字符不是自己期望的数据',1,1,1739779230,''),(5,3,'zig 会解决变量污染问题吗','zig 会解决变量污染问题吗',1,1,1739779230,''),(7,1,'zig 为什么会出现变量污染2','zig 为什么会出现变量污染2',2,1,1739779230,''),(8,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(9,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(10,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(11,1,'zig 什么时候把本地获取时区补上2','zig 什么时候把本地获取时区补上2',1,1,1739783728,''),(13,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(14,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(15,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(16,1,'zig 什么时候把本地获取时区补上','zig 什么时候把本地获取时区补上',0,1,1739783728,''),(18,5,'kkkkkkk','22222',0,1,1791646722,''),(19,7,'hhhhh','yyy',0,1,1791912316,''),(20,7,'999','88',0,1,1792075602,'');
/*!40000 ALTER TABLE `oryn_topic` ENABLE KEYS */;

#
# Structure for table "oryn_user"
#

DROP TABLE IF EXISTS `oryn_user`;
CREATE TABLE `oryn_user` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '账号，大小写字母数字',
  `cookie` varchar(62) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '密码',
  `sign` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT '' COMMENT '签名',
  `status` tinyint(1) DEFAULT '1' COMMENT '1-启用，0-禁用',
  `add_time` int(10) NOT NULL DEFAULT '0' COMMENT '添加时间',
  `add_ip` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '添加IP',
  PRIMARY KEY (`id`),
  KEY `cookie` (`cookie`)
) ENGINE=MyISAM AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='用户';

#
# Data for table "oryn_user"
#

/*!40000 ALTER TABLE `oryn_user` DISABLE KEYS */;
INSERT INTO `oryn_user` VALUES (1,'5d0e674217421f04c0cb6bd2','5d0e674217421f04c0cb6bd2','',1,1739779214,''),(2,'7162fc53f85d895c922f9df3','7162fc53f85d895c922f9df3','8',1,1739788731,''),(4,'2222e41227ddbdecd7085448','2222e41227ddbdecd7085448','',1,1791558432,''),(5,'0a784de6b1e1a59c0f9c6b1e','0a784de6b1e1a59c0f9c6b1e','',1,1791561010,''),(6,'yhygty87uj2','yhygty87uj2','uuu',1,1791646798,''),(7,'74c289898ca7ac5bbd3fc832','74c289898ca7ac5bbd3fc832','',1,1791912294,''),(8,'d8fd330ca705b4866fc35e52','d8fd330ca705b4866fc35e52','',1,1792076645,''),(9,'c571da14743623f39d6ce359','c571da14743623f39d6ce359','',1,1792076716,''),(10,'86281dcc1d38456e39583ect','86281dcc1d38456e39583ect','uuu',1,1792077046,''),(11,'515e116a40124a50434dd58u','515e116a40124a50434dd582','yy1',1,1792079513,'');
/*!40000 ALTER TABLE `oryn_user` ENABLE KEYS */;
