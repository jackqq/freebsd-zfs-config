# ZFS 文件服务器的维护

## 数据备份

### 准备工作

1. 连接离线备份盘之前，先打开 messages 日志文件监视系统消息，以了解新连接的磁盘对应的设备号。

   ```
   tail -F /var/log/messages
   ```

   假设观察到新连接的设备名为 _ada0_。

2. 初始化备份盘。

   ```
   gpart create -s gpt ada0
   gpart add -t freebsd-zfs -a 4K -s 1000G -l nas01.bak01 ada0
   ```

3. 加密。

   ```
   geli init gpt/nas01.bak01
   ```

### 第一次备份

1. 为整个存储快照，并锁定它，以防意外删除。

   ```
   zfs snapshot -r tank@`date +%F`
   zfs hold -r latest-backup tank@`date +%F`
   ```

2. 挂载加密的分区。

   ```
   geli attach gpt/nas01.bak01
   ```

3. 创建备份专用的 zpool。

   ```
   zpool create -R /bak01root bak01 gpt/nas01.bak01.eli
   ```

4. 将快照传输到备份文件系统。

   ```
   zfs send -R tank@`date +%F` | zfs receive -duvF bak01
   ```

5. 将备份存储池离线，并卸载加密分区。

   ```
   zpool export bak01
   geli detach gpt/nas01.bak01
   ```

6. 验证备份存储。

### 验证备份存储

1. 在一台离线的计算机上，用 Live CD 启动 FreeBSD，进入 Live 环境。

2. 挂载加密的磁盘分区，并导入 ZFS，但不挂载。

   ```
   geli attach gpt/nas01.bak01
   zpool import -N bak01
   ```

3. 开始 ZFS 的自动检查。

   ```
   zpool scrub bak01
   ```

4. 期间可以用 iostat 命令监测硬盘活动，最后用 status 命令确认完成。

   ```
   zpool iostat 3
   zpool status
   ```

5. 检查结束后，将备份存储池离线，并卸载加密分区。

   ```
   zpool export bak01
   geli detach gpt/nas01.bak01
   ```

### 增量备份

1. 为整个存储快照，并锁定它，以防意外删除。

   ```
   zfs snapshot -r tank@`date +%F`
   zfs hold -r latest-backup tank@`date +%F`
   ```

2. 挂载加密的分区。

   ```
   geli attach gpt/nas01.bak01
   ```

3. 导入备份专用的 zpool。务必使用 -N 参数禁止其挂载。

   ```
   zpool import -N -R /bak01root bak01
   ```

4. 找出上次备份的快照。

   ```
   zfs list -H -d 1 -t snapshot -o name tank | xargs zfs holds
   ```

   假设找出的快照为 _yyyy-mm-dd_。

5. 将快照增量传输到备份文件系统。

   ```
   zfs send -R -i yyyy-mm-dd tank@`date +%F` | zfs receive -duvF bak01
   ```

6. 将备份存储池离线，并卸载加密分区。

   ```
   zpool export bak01
   geli detach gpt/nas01.bak01
   ```

7. 验证备份存储。

8. 完成验证后，回到服务器上释放之前锁定的快照。

   ```
   zfs release -r latest-backup tank@yyyy-mm-dd
   ```

## 安全更新

### 系统更新

1. 配置系统更新通知。通过如下命令编辑 root 用户的 crontab：

   ```
   crontab -e
   ```

   在打开的编辑器中，写入如下行：

   ```
   0 7 * * *    /usr/sbin/freebsd-update cron
   ```

2. 部署更新的方法很简单，一般只需要执行：

   ```
   freebsd-update install
   ```

   然后重启系统即可。

### 软件包更新

1. 从日报邮件中获悉，或执行下列命令强制检查软件包的安全缺陷：

   ```
   pkg audit -F
   ```

2. 更新软件包数据库。

   ```
   pkg update
   ```

3. 安装软件包的最新版本。假设有问题的软件包名为 _pcre_。

   ```
   pkg install pcre
   ```

## 硬盘更换

1. 确定硬盘的物理位置。假设故障设备是 _da0_。数据盘的物理位置已经被标记为卷标，见 [INSTALL 文档](INSTALL.zh-cn.md)。

   ```
   gpart show -lp da0
   ```

  假设上述命令得出故障盘在 _1 号_槽位，热备盘在 _8 号_。

2. 用热备盘替换故障盘。

   ```
   zpool replace tank gpt/nas01.0.bay1 gpt/nas01.0.bay8
   ```

3. 将 1 号盘从 zpool 中脱离。

   ```
   zpool detach tank gpt/nas01.0.bay1
   ```

4. 再次确认硬盘已发生故障，为可选步骤。向磁盘写入数据然后读出，同时观察 messages 日志文件中的错误信息。

   ```
   dd if=/dev/zero of=/dev/gpt/nas01.0.bay1 bs=10M
   hd /dev/gpt/nas01.0.bay1
   ```

5. 将磁盘取出前，先修改其卷标，标记已损坏。

   ```
   gpart modify -i 1 -l nas01.0.bay1.FAIL-`date +%Y%m%d` da0
   ```

6. 更换物理硬盘。

7. 给新盘设置卷标并加入 zpool。

   ```
   gpart create -s gpt da0
   gpart add -t freebsd-zfs -a 100M -s 136G -l nas01.0.bay1 da0
   zpool add tank spare gpt/nas01.0.bay1
   ```


## 参考资料

- https://www.freebsd.org/doc/handbook/updating-upgrading-freebsdupdate.html
- https://forums.freebsd.org/threads/segmentation-fault-while-upgrading-from-10-0-release-to-10-1-release.48977/
