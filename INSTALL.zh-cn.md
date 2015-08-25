# ZFS 文件服务器的部署简介

准备工作。硬件配置：

   设备                    | 用途
   ----------------------- | ------------------------
   HP Proliant DL380 G5    | 服务器
   LSI SAS 3081E-R HBA     | 支持JBOD模式的磁盘连接
   Sandisk CZ33 U盘        | 引导操作系统，根文件系统
   魔羯 MC2685 eSATA扩展卡 | 连接外置式离线备份硬盘
   Seagate ST2000DM001     | 离线备份硬盘

## 硬件和操作系统

1. 配置 HBA。以 _LSI SAS 3081E-R_ 为例，在系统启动过程中，根据屏幕提示，按下 Ctrl+C 组合键进入配置程序，将其配置为 **Enabled OS Only** 模式。

2. 安装 FreeBSD 操作系统。

   - 把机器名配置为 **nas01._example.com_**，其中 _example.com_ 为局域网的域名。
   - 在系统组件的选择界面，把所有的选择都去掉。因为二进制包完全可以满足需要，故无需安装 ports，如果安装到 IO 性能较差的 U 盘，将可节省大量时间。
   - 在磁盘分区的步骤，先选择自动 UFS，通过品牌、型号从列表中辨认出 U 盘设备，完成分区向导。
   - 确认。
   - 等待系统文件解包后，进行网络、时区、用户等初始配置。

3. 系统重启后及时配置 /etc/hosts 文件，确保本机的机器名能正常解析。这是许多服务和程序正常运行的前提条件。

   ```
   192.168.xxx.xxx  nas01.example.com nas01
   192.168.xxx.xxx  nas01.example.com.
   ```

4. 为启动盘和交换分区设置卷标。修改 /etc/fstab 文件如下：

   ```
   # Device        Mountpoint      FStype  Options Dump    Pass#
   /dev/ufs/nas01root      /               ufs     rw,noatime      1       1
   /dev/label/nas01swap    none            swap    sw      0       0
   ```

   然后重启服务器，在引导菜单按 S 键进入 Single User Mode。给引导盘的分区打上卷标，并关闭 soft updates 日志，可显著提高 U 盘性能。

   ```
   glabel label nas01swap /dev/da8s1b
   tunefs -j disable -L nas01root /
   ```

   必须立即再次重启服务器。

   ```
   reboot
   ```

5. 每天汇报 ZFS 的状态并定期自检，在 /etc/periodic.conf 中配置如下行：

   ```
   daily_status_zfs_enable="YES"
   daily_scrub_zfs_enable="YES"
   ```

6. 配置 Sendmail 对外发送邮件。请见 [SENDMAIL 文档](SENDMAIL.md)。

## ZFS 文件系统

1. 对新数据盘分区，标记卷标。以便日后对应设备名和物理位置。

   ```
   gpart create -s gpt da0
   gpart add -t freebsd-zfs -a 100M -s 136G da0
   gpart modify -i 1 -l nas01.0.bay1 da0
   true > /dev/da0p1    # workaround for kern/154226
   gpart show –lp
   ```

2. 创建 zpool。

   ```
   zpool create tank mirror gpt/nas01.0.bay1 gpt/nas01.0.bay5
   zpool add tank mirror gpt/nas01.0.bay2 gpt/nas01.0.bay6
   zpool add tank mirror gpt/nas01.0.bay3 gpt/nas01.0.bay7
   zpool add tank spare gpt/nas01.0.bay8
   ```

3. 创建 ZFS 数据集。

   ```
   zfs create tank/test
   ```

## 将部分操作系统迁移到 ZFS

1. 创建ZFS数据集。

   ```
   zfs create -o compression=on   -o exec=on  -o setuid=off tank/tmp

   zfs create                                               tank/usr
   zfs create                                               tank/usr/home
   zfs create -o compression=lzjb             -o setuid=off tank/usr/ports
   zfs create -o compression=lzjb -o exec=off -o setuid=off tank/usr/src

   zfs create                                               tank/var
   zfs create -o compression=lzjb -o exec=off -o setuid=off tank/var/crash
   zfs create                     -o exec=off -o setuid=off tank/var/db
   zfs create -o compression=lzjb -o exec=on  -o setuid=off tank/var/db/pkg
   zfs create                     -o exec=off -o setuid=off tank/var/empty
   zfs create -o compression=lzjb -o exec=off -o setuid=off tank/var/log
   zfs create -o compression=gzip -o exec=off -o setuid=off tank/var/mail
   zfs create                     -o exec=off -o setuid=off tank/var/run
   zfs create -o compression=lzjb -o exec=on  -o setuid=off tank/var/tmp
   ```

2. 配置相应文件系统的权限。

   ```
   chmod 1777 /tank/tmp
   chmod 1777 /tank/var/tmp
   zfs set readonly=on tank/var/empty
   ```

3. 同步 /var 文件。

   ```
   rsync -a --delete /var /tank/var
   ```

4. 设置文件系统的挂载点。

   ```
   zfs set mountpoint=none tank/usr
   zfs set mountpoint=/usr/home tank/usr/home
   zfs set mountpoint=/usr/ports tank/usr/ports
   zfs set mountpoint=/usr/src tank/usr/src
   zfs set mountpoint=/tmp tank/tmp
   zfs set mountpoint=/var tank/var
   ```

5. 配置下次启动时自动挂载。编辑 /etc/rc.conf 追加：

   ```
   zfs_enable="YES"
   ```

## 安装 Samba 并加入活动目录

1. 通过二进制包安装 Samba 4。

   ```
   pkg install samba41
   ```

2. 准备操作系统的 Kerberos 默认配置。编辑 /etc/krb5.conf 如下：

   ```
   [libdefaults]
       default_realm = EXAMPLE.COM
       allow_weak_crypto = false
   ```

3. 进行 Samba 的全局配置，编辑 /usr/local/etc/smb4.conf 文件如下：

   ```
   [global]
       netbios name = NAS01
       workgroup = EXAMPLE
       security = ADS
       realm = EXAMPLE.COM
       kerberos method = system keytab
       client ldap sasl wrapping = sign

       os level = 8
       deadtime = 15
       dns proxy = no

       idmap config *:backend = tdb
       idmap config *:range = 100001-199999
       winbind use default domain = no
       template shell = /usr/sbin/nologin

       guest account = nobody
       map to guest = bad user

       load printers = no
       unix extensions = no
       case sensitive = no
       acl allow execute always = true
       nt acl support = yes
       map acl inherit = yes
       inherit permissions = yes
       inherit acls = yes
       store dos attributes = yes
       map archive = no
       map hidden = no
       map system = no
       map readonly = no

       vfs objects = shadow_copy2 zfsacl
       nfs4:mode = special
       nfs4:acedup = merge
       nfs4:chown = yes
       shadow:snapdir = .zfs/snapshot
       shadow:format = GMT-%Y.%m.%d-%H.%M.%S
       shadow:sort = desc
   ```

4. 加入活动目录，假设域管理员名叫 DomAdm。

   ```
   kinit DomAdm
   net ads join -k
   kdestroy
   ```

5. 配置 NSS，编辑 /etc/nsswitch.conf 在 passwd 和 group 两行中分别加上 winbind，如下：

   ```
   passwd: files winbind #compat
   group: files winbind #compat
   ```

## 创建共享并启动服务

1. 创建 ZFS 数据集并配置 ACL 模式和继承方式。

   ```
   zfs create tank/share
   zfs set aclinherit=passthrough tank/share
   zfs set aclmode=passthrough tank/share
   ```

2. 初始化该数据集的 ACL。

   ```
   cd /tank/share
   find . -type d -exec setfacl -m g:'EXAMPLE\Samba Read-Write Users':full_set:fd:allow {} \;
   find . -type f -exec setfacl -m g:'EXAMPLE\Samba Read-Write Users':full_set::allow {} \;
   ```

3. 在 Samba 配置文件 /usr/local/etc/smb4.conf 中追加共享配置：

   ```
   [share]
       path = /tank/share
       public = no
       write list = @"EXAMPLE\Samba Read-Write Users"
   ```

4. 配置操作系统允许 Samba 相关服务启动。在 /etc/rc.conf 文件中追加：

   ```
   samba_server_enable="YES"
   winbindd_enable="YES"
   ```

5. 执行以下命令重新启动 Samba 服务：

   ```
   service samba_server restart
   ```

## 文件系统快照

   创建定时任务实现自动创建快照，以及定期的快照整理建议。

   通过如下命令编辑 root 用户的 crontab：

   ```
   crontab -e
   ```

   在打开的编辑器中，写入如下行：

   ```
   0 6-23/2 * * *    /sbin/zfs snapshot tank/share@`TZ=GMT date +GMT-\%Y.\%m.\%d-\%H.\%M.\%S`
   0 3 * * 1         /usr/home/root/zfs_snapshots_to_clean.pl
   ```

   [zfs_snapshots_to_clean.pl](zfs_snapshots_to_clean.pl) 的内容请见相应文件。

## 验证与故障诊断

1. 在 Windows 域控制器上执行下面的命令，可验证 Samba 顺利的创建了服务主体名称（SPN）。

   ```
   setspn -l NAS01$
   ```

2. 在 FreeBSD 服务器上，执行 id 命令，可验证用户名解析机制正常工作，例如：

   ```
   id 'EXAMPLE\username'
   ```


## 参考资料

- https://h20566.www2.hpe.com/hpsc/doc/public/display?sp4ts.oid=1121516&docId=emr_na-c00710263&docLocale=en_US
- https://www.freebsd.org/doc/handbook/bsdinstall.html
- http://docs.oracle.com/cd/E19253-01/819-5461/6n7ht6quu/index.html
- https://wiki.freebsd.org/action/recall/RootOnZFS/GPTZFSBoot/Mirror?action=recall&rev=14
- http://bsdn00b.blogspot.com/2012/03/freebsd-with-zfs.html
- https://www.samba.org/samba/docs/man/manpages/smb.conf.5.html
