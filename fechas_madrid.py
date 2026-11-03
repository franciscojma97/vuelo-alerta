# Combinaciones ida/vuelta MTY-MAD: ida y regreso entre el 1 de febrero y el 31 de marzo de 2027,
# estancia de 14 a 21 días, solo en días con vuelo directo.
from datetime import date, timedelta
IDA = {1, 3, 4, 5}      # mar, jue, vie, sáb (lunes = 0)
VUELTA = {0, 1, 3, 5}   # lun, mar, jue, sáb
ini, fin = date(2027, 2, 1), date(2027, 3, 31)
d = ini
while d <= fin:
    if d.weekday() in IDA:
        for n in range(14, 22):
            v = d + timedelta(n)
            if v <= fin and v.weekday() in VUELTA:
                print(d, v)
    d += timedelta(1)
