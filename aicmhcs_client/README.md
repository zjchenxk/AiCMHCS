# 运行服务端

1、cd D:\MyProjects\Flutter\AiCMHCS\aicmhcs_server\

2、dart run .\bin\main.dart --apply-migrations


# 运行客户端

1、cd D:\MyProjects\Flutter\AiCMHCS\aicmhcs_flutter

2、flutter run -d chrome


# 默认登录帐号

1、系统管理员帐号：sysAdmin，密码：system@aicmhcs.com.cn


# 同步到GitHub

1、git config --global -l  # 显示代理

2、git config --global --unset http.proxy  # 清除http代理
3、git config --global --unset https.proxy  # 清除https代理

4、git config --global http.proxy http://127.0.0.1:21080  # 添加http代理
5、git config --global https.proxy https://127.0.0.1:21080  # 添加https代理


# GitHub Desktop 代理设置

C:\Users\zjche\AppData\Local\GitHubDesktop\GitHubDesktop.exe --proxy-server=socks5://127.0.0.1:21080  # 修改快捷方式，添加参数


# 备份还原本地PostgreSQL数据库

1、pg_dump -U postgres -d aicmhcs -F c -b -v -f D:/PostgreSQL/18/backups/aicmhcs.dump

2、pg_restore -U postgres -d aicmhcs -v D:/PostgreSQL/18/backups/aicmhcs.dump


# 备份还原Docker中的PostgreSQL数据库

1、打开cmd

2、进入 PostgreSQL 容器

docker exec -it <container_name> bash，如：docker exec -it aichmis_server-postgres-1 bash

3、备份数据库

pg_dump -U <username> -d <database_name> -F c -b -v -f /backup.dump，如：pg_dump -U postgres -d aicmhcs -F c -b -v -f /aicmhcs.dump

4、退出容器

exit

5、将备份文件拷出容器

docker cp <container_name>:/path/to/backup/file/backup /local/path，如：docker cp aichmis_server-postgres-1:/aicmhcs.dump d:/MyProjects/Serverpod/aicmhcs/docs

6、还原数据库

pg_restore -U root -d file_browser -v /path/to/backup.dump，如：pg_restore -U postgres -d aicmhcs -v d:/MyProjects/Serverpod/aicmhcs/docs/aicmhcs.dump


# 构建 Web 发布包

1、flutter clean

2、flutter pub get

3、flutter build web --release --dart-define=SERVER_URL=http://192.168.222.140:8080/

flutter build web --release --dart-define=SERVER_URL=/api/

若部署到子路径/aicmhcs/：flutter build web --release --base-href=/aicmhcs/

# 将 Web 发布包 上传到 linux 服务器

scp -r build/web/* root@192.168.222.140:/var/www/aicmhcs/

