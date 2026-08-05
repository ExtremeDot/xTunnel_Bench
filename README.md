# xTunnel_Bench

### Monitor Resources Ram and CPU usage while tunnel 

```
chmod +x /usr/local/bin/tunnel_monitor.sh

```
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


