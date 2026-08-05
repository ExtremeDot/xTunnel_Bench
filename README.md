# xTunnel_Bench
----

### Install Script

```
wget scrip
```

<img width="620" height="620" alt="image" src="https://github.com/user-attachments/assets/0917ab47-6e96-4ebe-8a5e-7a2096bfaa6c" />

### Install Dependencies and FRP Binaries

```
1. Install Dependencies & FRP v0.70.1
````


Then Check Server Location to be Correct

Server Location Status: [ KHAREJ ] or Server Location Status: [ IRAN ]
if Wrong change it via Menu:

```
6. Change Location Mode Manually (Toggle Iran/Kharej)
```

---

2- First Setup IRAN 

```
2. Setup FRP Server (Iran - Reverse Server)
```
to generate Authentication Token use command:

```
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo
```

<img width="654" height="464" alt="image" src="https://github.com/user-attachments/assets/b76e189c-5440-4f46-bcea-f24cdee0fdb9" />



---

3-  Setup Kharej Server

```
3. Setup FRP Client (Kharej - Reverse Client)
```

<img width="629" height="335" alt="image" src="https://github.com/user-attachments/assets/22ac86b6-63b1-480b-8e76-652fe11ff209" />



-------

### Monitor Resources Ram and CPU usage while tunnel 

```
chmod +x /usr/local/bin/tunnel_monitor.sh

```


----
### مثال های اجرایی سرویس مانیتورینگ منابع سرور

### روی سرور ایران:


#### Rathole
```
/usr/local/bin/tunnel_monitor.sh rathole rathole_iran.csv
```

#### FRP
```
/usr/local/bin/tunnel_monitor.sh frps frp_iran.csv

```
### روی سرور خارج:

#### Rathole
```
/usr/local/bin/tunnel_monitor.sh rathole rathole_kharej.csv
```

#### FRP

```
/usr/local/bin/tunnel_monitor.sh frpc frp_kharej.csv
```

### ۳. مشاهده خلاصه لاگ‌ها پس از اتمام تست
وقتی تست iperf3 تمام شد، در پنجره مانیتورینگ دکمه CTRL+C را بزنید تا اسکریپت متوقف شود.

سپس با دستور زیر می‌توانید میانگین و حداکثر مصرف CPU و RAM پردازنده را خروجی بگیرید:




```
awk -F',' 'NR>1 {cpu+=$3; ram+=$4; if($3>max_cpu) max_cpu=$3; if($4>max_ram) max_ram=$4; count++} END {print "Avg CPU: " cpu/count " % | Max CPU: " max_cpu " %\nAvg RAM: " ram/count " MB | Max RAM: " max_ram " MB"}' rathole_iran.csv
```

---


