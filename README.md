## Oryn-blog 博客系统

`Oryn-blog` 是使用 `gjallarhorn`, `odin-mysql` 及 `odin-jinja` 的 `odin` 博客系统


### 项目介绍

*  使用 `odin` 开发的简易博客系统
*  核心使用 `gjallarhorn`, `odin-mysql` 及 `odin-jinja` 等开发的博客系统
*  系统后台使用 `WeAdmin` 后端模板，非前后端分离项目


### 环境要求

 - odin >= dev-2026-10-nightly
 - Myzql


### 截图预览

<table>
    <tr>
        <td width="50%">
            <center>
                <img alt="登录" src="https://github.com/user-attachments/assets/fd468f4a-4293-42e8-8060-92fd99544623" />
            </center>
        </td>
        <td width="50%">
            <center>
                <img alt="控制台" src="https://github.com/user-attachments/assets/abf80955-8b1a-474f-b7d3-2f24f6f259cf" />
            </center>
        </td>
    </tr>
    <tr>
        <td width="50%">
            <center>
                <img alt="文章管理" src="https://github.com/user-attachments/assets/2d26fda4-4eaf-4277-b9d0-c3c763f12ce2" />
            </center>
        </td>
        <td width="50%">
            <center>
                <img alt="分类管理" src="https://github.com/user-attachments/assets/8be3ed5b-659f-46b5-8c7b-14bf57c70783" />
            </center>
        </td>
    </tr>
</table>

更多截图
[Oryn-blog 截图](https://github.com/deatil/oryn-blog/issues/1)


### 安装及开发步骤

1. 首先克隆项目到本地

```sh
git clone https://github.com/deatil/oryn-blog.git
```

2. 然后配置数据库等信息

```
/oryn/app/config/config.odin
```

3. 最后导入 sql 数据到数据库

```
/docs/oryn_blog.sql
```

4. 运行测试

```sh
odin run . -collection:oryn=oryn
```

6. 后台登录账号及密码：`admin` / `1234567`, 后台登录地址: `/admin/auth/login`


### 特别鸣谢

感谢以下的项目,排名不分先后

 - [Gjallarhorn](https://github.com/Lvcky-gg/Gjallarhorn)

 - [odin-mysql](https://github.com/laytan/odin-mysql)
 
 - [odin-jinja](https://github.com/insanai/guidedog_odin/tree/main/lib/jinja)


### 开源协议

*  `zig-say` 遵循 `Apache2` 开源协议发布，在保留本系统版权的情况下提供个人及商业免费使用。


### 版权

*  该系统所属版权归 deatil(https://github.com/deatil) 所有。
