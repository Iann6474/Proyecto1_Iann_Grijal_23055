;************************
; Universidad del Valle de Guatemala
; IE2023: Programación de Microcontroladores
; Reloj Digital 24 horas con alrma
;
; Descripción: Reloj 24 horas con modos de fecha y también con alarma programable
;              
;
; Hardware: ATMega328P
;************************



.include "m328pdef.inc"

; definición de pines para displays
.equ DISPLAY_UNIDADES = PC5     ; Unidades minutos (reloj) o día (fecha)
.equ DISPLAY_DECENAS = PC4      ; Decenas minutos (reloj) o día (fecha)
.equ DISPLAY_UNIDADES_SUPERIOR = PC3  ; Unidades horas (reloj) o mes (fecha)
.equ DISPLAY_DECENAS_SUPERIOR = PC2   ; Decenas horas (reloj) o mes (fecha)
.equ LED_INDICADOR = PC1        ; LED indicador segundos/parpadeo
.equ PIN_ALARMA = PC0           ; Pin para el sonido de alarma (cambiado de PD7)
.equ LED_ALARMA = PB5           ; LED indicador de alarma activa (cambiado a PB5)

; definición de pines de botones
.equ BTN_INC_INFERIOR = PB0     ; Incremento minutos/día y apagar alarma
.equ BTN_DEC_INFERIOR = PB3     ; Decremento minutos/día y desprogramar alarma
.equ BTN_INC_SUPERIOR = PB4     ; Incremento horas/mes y cambio de modo
.equ BTN_DEC_SUPERIOR = PB1     ; Decremento horas/mes y configurar alarma
.equ BTN_MODO = PB2             ; Cambio entre modo normal y edición, confirmar alarma

; estados del sistema
.equ ESTADO_RELOJ = 0           ; Mostrando reloj (hora) sin editar
.equ ESTADO_EDICION_RELOJ = 1   ; Editando reloj (hora)
.equ ESTADO_FECHA = 2           ; Mostrando fecha sin editar
.equ ESTADO_EDICION_FECHA = 3   ; Editando fecha
.equ ESTADO_EDICION_ALARMA = 4  ; Editando alarma

; variables en SRAM
.dseg
.org 0x0100
tabla_digitos: .byte 10        ; tabla de conversión a 7 segmentos
dias_por_mes: .byte 12         ; tabla con días por mes (1-12)

; variables para el reloj
contador_unidades_min: .byte 1  ; unidades de minutos (0-9)
contador_decenas_min: .byte 1   ; decenas de minutos (0-5)
contador_unidades_hora: .byte 1 ; unidades de hora (0-9)
contador_decenas_hora: .byte 1  ; decenas de hora (0-2)
contador_minutos: .byte 1       ; contador total de minutos (0-59)
contador_horas: .byte 1         ; contador total de horas (0-23)

; variables para la fecha
contador_unidades_dia: .byte 1  ; unidades de día (0-9)
contador_decenas_dia: .byte 1   ; decenas de día (0-3)
contador_unidades_mes: .byte 1  ; unidades de mes (0-9)
contador_decenas_mes: .byte 1   ; decenas de mes (0-1)
contador_dia: .byte 1           ; contador total de día (1-31)
contador_mes: .byte 1           ; contador total de mes (1-12)

; variables para la alarma
alarma_unidades_min: .byte 1    ; unidades de minutos para alarma (0-9)
alarma_decenas_min: .byte 1     ; decenas de minutos para alarma (0-5)
alarma_unidades_hora: .byte 1   ; unidades de hora para alarma (0-9)
alarma_decenas_hora: .byte 1    ; decenas de hora para alarma (0-2)
alarma_minutos: .byte 1         ; valor total de minutos para alarma (0-59)
alarma_horas: .byte 1           ; valor total de horas para alarma (0-23)
alarma_activa: .byte 1          ; estado de la alarma (0 = desactivada, 1 = activada)
alarma_sonando: .byte 1         ; indica si la alarma está sonando (0 = no, 1 = sí)
contador_alarma: .byte 1        ; contador para la duración de la alarma (max 30 segundos)

; variables generales
contador_timer: .byte 1        ; contador para la interrupción del timer
contador_segundos: .byte 1     ; contador de segundos (0-59)
estado_led: .byte 1            ; estado del LED (0 = apagado, 1 = encendido)
contador_parpadeo: .byte 1     ; contador para parpadeo del LED
btn_estado_previo: .byte 5     ; estado previo de los 5 botones
estado_sistema: .byte 1        ; estado actual del sistema

.cseg
.org 0x0000
    rjmp RESET                 ; vector de reset

.org OVF0addr
    rjmp TIMER0_OVF            ; vector de interrupción del Timer0

RESET:
    ; configuración de la pila
    ldi r16, HIGH(RAMEND)
    out SPH, r16
    ldi r16, LOW(RAMEND)
    out SPL, r16

    ; inicialización de puertos
    ; PC5-PC0 como salidas (displays, LEDs indicadores y alarma)
    ldi r16, (1<<DISPLAY_UNIDADES)|(1<<DISPLAY_DECENAS)|(1<<DISPLAY_UNIDADES_SUPERIOR)|(1<<DISPLAY_DECENAS_SUPERIOR)|(1<<LED_INDICADOR)|(1<<PIN_ALARMA)
    out DDRC, r16

    ; puerto D (PD0-PD6) como salidas (segmentos a-g)
    ldi r16, 0b01111111        ; PD0-PD6 como salidas
    out DDRD, r16
    
    ; Configurar PB5 como salida para LED de alarma (mantener PB0-PB4 como entradas)
    in r16, DDRB              ; leer valor actual de DDRB
    ori r16, (1<<LED_ALARMA)  ; Establecer solo el bit PB5 como salida
    out DDRB, r16             ; escribir de nuevo el registro
    
    ; inicializar PC0 (alarma) en estado bajo
    cbi PORTC, PIN_ALARMA
    
    ; inicializar PB5 (LED de alarma) en estado bajo
    cbi PORTB, LED_ALARMA
    
    ; configurar pines de botones como entradas con pull-up
    ldi r16, 0                ; limpiar r16
    ori r16, (1<<BTN_INC_INFERIOR)|(1<<BTN_DEC_INFERIOR)|(1<<BTN_INC_SUPERIOR)|(1<<BTN_DEC_SUPERIOR)|(1<<BTN_MODO)
    out PORTB, r16            ; activar resistencias pull-up solo para los botones
    
    ; configurar pines de botones como entradas con pull-up (después de configurar PB5)
    ; Nota: ya configuramos DDRB en el paso anterior para que PB5 sea salida y PB0-PB4 sean entradas

    ; inicialización de contadores de reloj (00:00 por defecto)
    ldi r16, 0
    sts contador_unidades_min, r16
    sts contador_decenas_min, r16
    sts contador_unidades_hora, r16
    sts contador_decenas_hora, r16
    sts contador_minutos, r16
    sts contador_horas, r16
    
    ; inicialización de contadores de fecha (01/01 por defecto)
    ldi r16, 1
    sts contador_unidades_dia, r16
    ldi r16, 0
    sts contador_decenas_dia, r16
    ldi r16, 1
    sts contador_unidades_mes, r16
    ldi r16, 0
    sts contador_decenas_mes, r16
    ldi r16, 1
    sts contador_dia, r16
    sts contador_mes, r16
    
    ; inicialización de variables de alarma
    ldi r16, 0
    sts alarma_unidades_min, r16
    sts alarma_decenas_min, r16
    sts alarma_unidades_hora, r16
    sts alarma_decenas_hora, r16
    sts alarma_minutos, r16
    sts alarma_horas, r16
    sts alarma_activa, r16      ; alarma desactivada por defecto
    sts alarma_sonando, r16     ; alarma no sonando por defecto
    sts contador_alarma, r16    ; contador de duración en 0
    
    ; LED de alarma inicialmente apagado
    cbi PORTC, LED_ALARMA
    
    ; inicializar otros contadores
    ldi r16, 0
    sts contador_timer, r16
    sts contador_segundos, r16
    sts contador_parpadeo, r16
    
    ; inicializar estado del sistema
    ldi r16, ESTADO_RELOJ
    sts estado_sistema, r16
    
    ; iniciar con el LED encendido
    ldi r16, 1
    sts estado_led, r16
    
    ; inicializar estados previos de botones 
    ldi r16, 1                  ; botones liberados (con pull-up = 1)
    sts btn_estado_previo+0, r16  ; botón incremento inferior
    sts btn_estado_previo+1, r16  ; botón decremento inferior
    sts btn_estado_previo+2, r16  ; botón incremento superior
    sts btn_estado_previo+3, r16  ; botón decremento superior
    sts btn_estado_previo+4, r16  ; botón cambio de modo

    ; inicialización de la tabla de dígitos
    rcall INICIAR_TABLA_DIGITOS
    
    ; inicialización de tabla de días por mes
    rcall INICIAR_TABLA_DIAS

    ; configuración del Timer0
    ldi r16, 0                   ; asegurar que el Timer0 esté apagado inicialmente
    out TCCR0A, r16
    ldi r16, (1<<CS02)|(1<<CS00) ; preescalado 1024
    out TCCR0B, r16
    ldi r16, (1<<TOIE0)          ; habilitar interrupción por desbordamiento
    sts TIMSK0, r16

    ; habilitar interrupciones globales
    sei

MAIN_LOOP:
    ; verificar si la alarma está sonando y manejarla
    rcall VERIFICAR_ALARMA_SONANDO
    
    ; mostrar los dígitos en los displays (multiplexado) según el modo actual
    rcall MOSTRAR_DISPLAYS
    
    ; verificar botón para cambiar entre modo reloj y fecha
    rcall VERIFICAR_CAMBIO_MODO_DISPLAY
    
    ; verificar botón de modo edición/confirmar
    rcall VERIFICAR_MODO_EDICION
    
    ; verificar botones de alarma (en modo reloj normal)
    rcall VERIFICAR_BOTONES_ALARMA
    
    ; verificar botones de ajuste según el estado actual
    lds r16, estado_sistema
    cpi r16, ESTADO_RELOJ
    breq MAIN_CONTINUE         ; si estamos en modo reloj normal, no verificar botones de edición
    
    cpi r16, ESTADO_FECHA
    breq MAIN_CONTINUE         ; si estamos en modo fecha normal, no verificar botones de edición
    
    ; en modo edición (reloj, fecha o alarma), verificar botones para ajustar
    rcall VERIFICAR_BOTONES
    
MAIN_CONTINUE:
    rjmp MAIN_LOOP

; verificar si la alarma está sonando y manejarla
VERIFICAR_ALARMA_SONANDO:
    push r16
    push r17
    
    ; verificar si la alarma está sonando
    lds r16, alarma_sonando
    cpi r16, 1
    brne ALARMA_NO_SONANDO
    
    ; la alarma está sonando, verificar si se superó el tiempo máximo (30 seg)
    lds r16, contador_alarma
    cpi r16, 30
    brlo ALARMA_CONTINUA_SONANDO
    
    ; se superó el tiempo máximo, apagar la alarma
    rcall APAGAR_ALARMA
    rjmp ALARMA_NO_SONANDO
    
ALARMA_CONTINUA_SONANDO:
    ; hacer que la alarma suene continuamente (mantener en estado alto)
    sbi PORTC, PIN_ALARMA       ; mantener la alarma encendida en PC0
    
ALARMA_NO_SONANDO:
    pop r17
    pop r16
    ret

; verificar botones para manejar la alarma en modo reloj normal
VERIFICAR_BOTONES_ALARMA:
    push r16
    push r17
    
    ; solo verificar en modo reloj normal
    lds r16, estado_sistema
    cpi r16, ESTADO_RELOJ
    breq CONTINUAR_VERIFICACION_ALARMA  ; invertimos lógica: si es ESTADO_RELOJ continuar
    rjmp FIN_VERIFICAR_BOTONES_ALARMA   ; si no es ESTADO_RELOJ, salir directamente
    
CONTINUAR_VERIFICACION_ALARMA:
    in r16, PINB                 ; leer estado actual de los botones
    
    ; verificar PB1 (entrar en modo programación de alarma)
    sbrc r16, BTN_DEC_SUPERIOR   ; si el bit está a 1 (botón no presionado), saltar
    rjmp CHECK_BTN_APAGAR_ALARMA ; botón no presionado, verificar siguiente
    
    ; botón PB1 presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+3
    cpi r17, 1                   ; ¿estaba liberado antes?
    brne CHECK_BTN_APAGAR_ALARMA ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación para entrar en modo alarma
    ldi r17, 0                   ; actualizar estado a presionado
    sts btn_estado_previo+3, r17
    
    ; cambiar a modo edición de alarma
    ldi r17, ESTADO_EDICION_ALARMA
    sts estado_sistema, r17
    
    ; inicializar valores de alarma si no estaba activa
    lds r17, alarma_activa
    cpi r17, 1
    breq CHECK_BTN_APAGAR_ALARMA ; si ya estaba activa, mantener valores actuales
    
    ; inicializar con hora actual
    lds r17, contador_horas
    sts alarma_horas, r17
    lds r17, contador_minutos
    sts alarma_minutos, r17
    rcall ACTUALIZAR_DISPLAYS_ALARMA
    
    rjmp CHECK_BTN_APAGAR_ALARMA
    
CHECK_BTN_APAGAR_ALARMA:
    ; actualizar estado previo del botón PB1
    sbrs r16, BTN_DEC_SUPERIOR   ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_APAGAR_REAL   ; botón sigue presionado
    ldi r17, 1                   ; botón liberado
    sts btn_estado_previo+3, r17
    
CHECK_BTN_APAGAR_REAL:
    ; verificar PB0 (apagar alarma si está sonando)
    sbrc r16, BTN_INC_INFERIOR   ; si el bit está a 1 (botón no presionado), saltar
    rjmp CHECK_BTN_DESPROGRAMAR  ; botón no presionado, verificar siguiente
    
    ; botón PB0 presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+0
    cpi r17, 1                   ; ¿estaba liberado antes?
    brne CHECK_BTN_DESPROGRAMAR  ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación para apagar alarma
    ldi r17, 0                   ; actualizar estado a presionado
    sts btn_estado_previo+0, r17
    
    ; verificar si la alarma está sonando
    lds r17, alarma_sonando
    cpi r17, 1
    brne CHECK_BTN_DESPROGRAMAR  ; si no está sonando, ignorar
    
    ; apagar la alarma
    rcall APAGAR_ALARMA
    rjmp CHECK_BTN_DESPROGRAMAR
    
CHECK_BTN_DESPROGRAMAR:
    ; actualizar estado previo del botón PB0
    sbrs r16, BTN_INC_INFERIOR   ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DESP_REAL     ; botón sigue presionado
    ldi r17, 1                   ; botón liberado
    sts btn_estado_previo+0, r17
    
CHECK_BTN_DESP_REAL:
    ; verificar PB3 (desprogramar alarma)
    sbrc r16, BTN_DEC_INFERIOR   ; si el bit está a 1 (botón no presionado), saltar
    rjmp FINAL_VERIFICAR_ALARMA  ; botón no presionado, salir
    
    ; botón PB3 presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+1
    cpi r17, 1                   ; ¿estaba liberado antes?
    brne FINAL_VERIFICAR_ALARMA  ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación para desprogramar alarma
    ldi r17, 0                   ; actualizar estado a presionado
    sts btn_estado_previo+1, r17
    
    ; desactivar la alarma
    ldi r17, 0
    sts alarma_activa, r17
    
    ; apagar LED de alarma en PB5
    cbi PORTB, LED_ALARMA
    
    ; si la alarma estaba sonando, apagarla también
    lds r17, alarma_sonando
    cpi r17, 1
    brne FINAL_VERIFICAR_ALARMA
    rcall APAGAR_ALARMA
    
FINAL_VERIFICAR_ALARMA:
    ; actualizar estado previo del botón PB3
    sbrs r16, BTN_DEC_INFERIOR   ; si el bit está a 0 (presionado), saltar
    rjmp BTN_ALARMA_EXIT         ; botón sigue presionado
    ldi r17, 1                   ; botón liberado
    sts btn_estado_previo+1, r17
    
BTN_ALARMA_EXIT:
    ; No es necesario hacer nada más
    
FIN_VERIFICAR_BOTONES_ALARMA:
    pop r17
    pop r16
    ret

; apagar la alarma cuando está sonando
APAGAR_ALARMA:
    push r16
    
    ; apagar el pin de la alarma
    cbi PORTC, PIN_ALARMA       ; Apagar señal de alarma en PC0
    
    ; resetear variables
    ldi r16, 0
    sts alarma_sonando, r16
    sts contador_alarma, r16
    
    pop r16
    ret

; actualizar los displays de alarma
ACTUALIZAR_DISPLAYS_ALARMA:
    push r16
    push r17
    push r18
    
    ; convertir horas a dígitos
    lds r16, alarma_horas
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo ALARMA_HORA_DIGITOS ; si es menor que 10, saltar

ALARMA_DECENAS_LOOP_HORA:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge ALARMA_DECENAS_LOOP_HORA ; si quedan más de 10, repetir
    
ALARMA_HORA_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts alarma_unidades_hora, r16  ; guardar unidades
    sts alarma_decenas_hora, r17   ; guardar decenas
    
    ; convertir minutos a dígitos
    lds r16, alarma_minutos
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo ALARMA_MIN_DIGITOS ; si es menor que 10, saltar

ALARMA_DECENAS_LOOP_MIN:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge ALARMA_DECENAS_LOOP_MIN ; si quedan más de 10, repetir
    
ALARMA_MIN_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts alarma_unidades_min, r16  ; guardar unidades
    sts alarma_decenas_min, r17   ; guardar decenas
    
    pop r18
    pop r17
    pop r16
    ret

; verificar botón para cambiar entre modo reloj y fecha (PB4)
VERIFICAR_CAMBIO_MODO_DISPLAY:
    push r16
    push r17
    
    ; solo permitir cambio de modo si no estamos en modo edición
    lds r17, estado_sistema
    cpi r17, ESTADO_EDICION_RELOJ
    breq SALIR_CAMBIO_MODO      ; si estamos editando reloj, no permitir cambio
    
    cpi r17, ESTADO_EDICION_FECHA
    breq SALIR_CAMBIO_MODO      ; si estamos editando fecha, no permitir cambio
    
    cpi r17, ESTADO_EDICION_ALARMA
    breq SALIR_CAMBIO_MODO      ; si estamos editando alarma, no permitir cambio
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; verificar botón de cambio modo display (PB4)
    sbrc r16, BTN_INC_SUPERIOR  ; si el bit está a 1 (botón no presionado), saltar
    rjmp CHECK_BTN_CAMBIO_MODO  ; botón no presionado, verificar si fue liberado
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+2
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne SALIR_CAMBIO_MODO      ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación para cambiar entre reloj y fecha
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+2, r17
    
    ; cambiar estado del sistema: reloj <-> fecha
    lds r17, estado_sistema
    cpi r17, ESTADO_RELOJ
    brne CAMBIAR_A_RELOJ_DESDE_FECHA
    
    ; cambiar a modo fecha
    ldi r17, ESTADO_FECHA
    sts estado_sistema, r17
    rjmp SALIR_CAMBIO_MODO
    
CAMBIAR_A_RELOJ_DESDE_FECHA:
    ; cambiar a modo reloj
    ldi r17, ESTADO_RELOJ
    sts estado_sistema, r17
    
SALIR_CAMBIO_MODO:
    pop r17
    pop r16
    ret
    
CHECK_BTN_CAMBIO_MODO:
    ; actualizar estado previo si el botón fue liberado
    lds r17, btn_estado_previo+2
    sbrs r16, BTN_INC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp SALIR_CAMBIO_MODO      ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+2, r17
    rjmp SALIR_CAMBIO_MODO

; verificar botón para cambiar entre modo normal y edición (PB2)
VERIFICAR_MODO_EDICION:
    push r16
    push r17
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; verificar botón de modo edición/confirmar (PB2)
    sbrc r16, BTN_MODO          ; si el bit está a 1 (botón no presionado), saltar
    rjmp CHECK_BTN_MODO_EDICION ; botón no presionado, verificar si fue liberado
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+4
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne SALIR_MODO_EDICION     ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación del botón modo/confirmar
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+4, r17
    
    ; cambiar estado según modo actual
    lds r17, estado_sistema
    cpi r17, ESTADO_RELOJ
    breq CAMBIAR_A_EDICION_RELOJ
    
    cpi r17, ESTADO_EDICION_RELOJ
    breq CAMBIAR_A_RELOJ_NORMAL
    
    cpi r17, ESTADO_FECHA
    breq CAMBIAR_A_EDICION_FECHA
    
    cpi r17, ESTADO_EDICION_FECHA
    breq CAMBIAR_A_FECHA_NORMAL
    
    cpi r17, ESTADO_EDICION_ALARMA
    breq CONFIRMAR_ALARMA
    
    rjmp SALIR_MODO_EDICION
    
CAMBIAR_A_EDICION_RELOJ:
    ldi r17, ESTADO_EDICION_RELOJ
    sts estado_sistema, r17
    rjmp SALIR_MODO_EDICION
    
CAMBIAR_A_RELOJ_NORMAL:
    ldi r17, ESTADO_RELOJ
    sts estado_sistema, r17
    
    ; reiniciar contador de segundos para comenzar a contar desde cero
    ldi r17, 0
    sts contador_segundos, r17
    sts contador_timer, r17
    rjmp SALIR_MODO_EDICION
    
CAMBIAR_A_EDICION_FECHA:
    ldi r17, ESTADO_EDICION_FECHA
    sts estado_sistema, r17
    rjmp SALIR_MODO_EDICION
    
CAMBIAR_A_FECHA_NORMAL:
    ldi r17, ESTADO_FECHA
    sts estado_sistema, r17
    rjmp SALIR_MODO_EDICION
    
CONFIRMAR_ALARMA:
    ; activar la alarma con los valores configurados
    ldi r17, 1
    sts alarma_activa, r17
    
    ; encender LED de alarma activa en PB5
    sbi PORTB, LED_ALARMA
    
    ; volver a modo reloj
    ldi r17, ESTADO_RELOJ
    sts estado_sistema, r17
    rjmp SALIR_MODO_EDICION
    
CHECK_BTN_MODO_EDICION:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_MODO          ; si el bit está a 0 (presionado), saltar
    rjmp SALIR_MODO_EDICION     ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+4, r17
    
SALIR_MODO_EDICION:
    pop r17
    pop r16
    ret

; verificar el estado de los botones y ajustar según el modo de edición
VERIFICAR_BOTONES:
    push r16
    push r17
    push r18
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; determinar qué verificar según el estado actual
    lds r17, estado_sistema
    cpi r17, ESTADO_EDICION_RELOJ
    breq VERIFICAR_BOTONES_RELOJ
    
    cpi r17, ESTADO_EDICION_FECHA
    breq VERIFICAR_BOTONES_FECHA
    
    cpi r17, ESTADO_EDICION_ALARMA
    breq VERIFICAR_BOTONES_ALARMA_EDICION
    
    rjmp SALIR_VERIFICAR_BOTONES
    
VERIFICAR_BOTONES_RELOJ:
    ; verificar botones para editar reloj
    rcall VERIFICAR_BOTONES_EDICION_RELOJ
    rjmp SALIR_VERIFICAR_BOTONES
    
VERIFICAR_BOTONES_FECHA:
    ; verificar botones para editar fecha
    rcall VERIFICAR_BOTONES_EDICION_FECHA
    rjmp SALIR_VERIFICAR_BOTONES
    
VERIFICAR_BOTONES_ALARMA_EDICION:
    ; verificar botones para editar alarma
    rcall VERIFICAR_BOTONES_EDICION_ALARMA
    
SALIR_VERIFICAR_BOTONES:
    pop r18
    pop r17
    pop r16
    ret

; verificar botones para editar alarma
VERIFICAR_BOTONES_EDICION_ALARMA:
    push r16
    push r17
    push r18
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; verificar botón de incremento minutos (PB0)
    sbrc r16, BTN_INC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_MIN_ALARMA   ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+0
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_MIN_ALARMA   ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de minutos de alarma
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+0, r17
    rcall INCREMENTAR_MINUTOS_ALARMA
    rjmp CHECK_DEC_MIN_ALARMA
    
CHECK_DEC_MIN_ALARMA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_MIN_ALARMA ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+0, r17

CHECK_BTN_DEC_MIN_ALARMA:
    ; verificar botón de decremento de minutos (PB3)
    sbrc r16, BTN_DEC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_INC_HORA_ALARMA  ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+1
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_INC_HORA_ALARMA  ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de minutos de alarma
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+1, r17
    rcall DECREMENTAR_MINUTOS_ALARMA
    rjmp CHECK_INC_HORA_ALARMA
    
CHECK_INC_HORA_ALARMA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_INC_HORA_ALARMA ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+1, r17

CHECK_BTN_INC_HORA_ALARMA:
    ; verificar botón de incremento de horas (PB4)
    sbrc r16, BTN_INC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_HORA_ALARMA  ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+2
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_HORA_ALARMA  ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de horas de alarma
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+2, r17
    rcall INCREMENTAR_HORAS_ALARMA
    rjmp CHECK_DEC_HORA_ALARMA
    
CHECK_DEC_HORA_ALARMA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_HORA_ALARMA ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+2, r17

CHECK_BTN_DEC_HORA_ALARMA:
    ; verificar botón de decremento de horas (PB1)
    sbrc r16, BTN_DEC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp END_BTN_CHECK_ALARMA   ; botón no presionado, finalizar
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+3
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne END_BTN_CHECK_ALARMA   ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de horas de alarma
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+3, r17
    rcall DECREMENTAR_HORAS_ALARMA
    rjmp END_BTN_CHECK_ALARMA
    
END_BTN_CHECK_ALARMA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp BTN_CHECK_EXIT_ALARMA  ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+3, r17

BTN_CHECK_EXIT_ALARMA:
    pop r18
    pop r17
    pop r16
    ret

; incrementar minutos de alarma (0-59)
INCREMENTAR_MINUTOS_ALARMA:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, alarma_minutos
    
    ; incrementar contador
    inc r16
    
    ; verificar límite (0-59)
    cpi r16, 60
    brlo GUAR_MINUTOS_ALARMA_CONTADOR
    
    ; reset a 0 si llegó a 60
    ldi r16, 0
    
GUAR_MINUTOS_ALARMA_CONTADOR:
    ; guardar nuevo valor
    sts alarma_minutos, r16
    
    ; actualizar display
    rcall ACTUALIZAR_DISPLAYS_ALARMA
    
    pop r17
    pop r16
    ret

; decrementar minutos de alarma (0-59)
DECREMENTAR_MINUTOS_ALARMA:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, alarma_minutos
    
    ; si ya está en 0, ir a 59
    cpi r16, 0
    brne DEC_MIN_ALARMA_NORMAL
    
    ldi r16, 59
    rjmp GUAR_MINUTOS_ALARMA_CONTADOR_DEC
    
DEC_MIN_ALARMA_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_MINUTOS_ALARMA_CONTADOR_DEC:
    ; guardar nuevo valor
    sts alarma_minutos, r16
    
    ; actualizar display
    rcall ACTUALIZAR_DISPLAYS_ALARMA
    
    pop r17
    pop r16
    ret

; incrementar horas de alarma (0-23)
INCREMENTAR_HORAS_ALARMA:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, alarma_horas
    
    ; incrementar contador
    inc r16
    
    ; verificar límite (0-23)
    cpi r16, 24
    brlo GUAR_HORAS_ALARMA_CONTADOR
    
    ; reset a 0 si llegó a 24
    ldi r16, 0
    
GUAR_HORAS_ALARMA_CONTADOR:
    ; guardar nuevo valor
    sts alarma_horas, r16
    
    ; actualizar display
    rcall ACTUALIZAR_DISPLAYS_ALARMA
    
    pop r17
    pop r16
    ret

; decrementar horas de alarma (0-23)
DECREMENTAR_HORAS_ALARMA:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, alarma_horas
    
    ; si ya está en 0, ir a 23
    cpi r16, 0
    brne DEC_HORA_ALARMA_NORMAL
    
    ldi r16, 23
    rjmp GUAR_HORAS_ALARMA_CONTADOR_DEC
    
DEC_HORA_ALARMA_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_HORAS_ALARMA_CONTADOR_DEC:
    ; guardar nuevo valor
    sts alarma_horas, r16
    
    ; actualizar display
    rcall ACTUALIZAR_DISPLAYS_ALARMA
    
    pop r17
    pop r16
    ret

; verificar botones para editar reloj
VERIFICAR_BOTONES_EDICION_RELOJ:
    push r16
    push r17
    push r18
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; verificar botón de incremento minutos (PB0)
    sbrc r16, BTN_INC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_MIN          ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+0
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_MIN          ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de minutos
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+0, r17
    rcall INCREMENTAR_MINUTOS
    rjmp CHECK_DEC_MIN
    
CHECK_DEC_MIN:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_MIN      ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+0, r17

CHECK_BTN_DEC_MIN:
    ; verificar botón de decremento de minutos (PB3)
    sbrc r16, BTN_DEC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_INC_HORA         ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+1
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_INC_HORA         ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de minutos
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+1, r17
    rcall DECREMENTAR_MINUTOS
    rjmp CHECK_INC_HORA
    
CHECK_INC_HORA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_INC_HORA     ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+1, r17

CHECK_BTN_INC_HORA:
    ; verificar botón de incremento de horas (PB4)
    sbrc r16, BTN_INC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_HORA         ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+2
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_HORA         ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de horas
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+2, r17
    rcall INCREMENTAR_HORAS
    rjmp CHECK_DEC_HORA
    
CHECK_DEC_HORA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_HORA     ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+2, r17

CHECK_BTN_DEC_HORA:
    ; verificar botón de decremento de horas (PB1)
    sbrc r16, BTN_DEC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp END_BTN_CHECK_RELOJ    ; botón no presionado, finalizar
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+3
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne END_BTN_CHECK_RELOJ    ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de horas
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+3, r17
    rcall DECREMENTAR_HORAS
    rjmp END_BTN_CHECK_RELOJ
    
END_BTN_CHECK_RELOJ:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp BTN_CHECK_EXIT_RELOJ   ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+3, r17

BTN_CHECK_EXIT_RELOJ:
    pop r18
    pop r17
    pop r16
    ret

; verificar botones para editar fecha
VERIFICAR_BOTONES_EDICION_FECHA:
    push r16
    push r17
    push r18
    
    in r16, PINB                ; leer estado actual de los botones
    
    ; verificar botón de incremento día (PB0)
    sbrc r16, BTN_INC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_DIA          ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+0
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_DIA          ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de día
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+0, r17
    rcall INCREMENTAR_DIA
    rjmp CHECK_DEC_DIA
    
CHECK_DEC_DIA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_DIA      ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+0, r17

CHECK_BTN_DEC_DIA:
    ; verificar botón de decremento de día (PB3)
    sbrc r16, BTN_DEC_INFERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_INC_MES          ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+1
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_INC_MES          ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de día
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+1, r17
    rcall DECREMENTAR_DIA
    rjmp CHECK_INC_MES
    
CHECK_INC_MES:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_INFERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_INC_MES      ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+1, r17

CHECK_BTN_INC_MES:
    ; verificar botón de incremento de mes (PB4)
    sbrc r16, BTN_INC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp CHECK_DEC_MES          ; botón no presionado, verificar siguiente
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+2
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne CHECK_DEC_MES          ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de incremento de mes
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+2, r17
    rcall INCREMENTAR_MES
    rjmp CHECK_DEC_MES
    
CHECK_DEC_MES:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_INC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp CHECK_BTN_DEC_MES      ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+2, r17

CHECK_BTN_DEC_MES:
    ; verificar botón de decremento de mes (PB1)
    sbrc r16, BTN_DEC_SUPERIOR  ; si el bit está a 1 (no presionado), saltar
    rjmp END_BTN_CHECK_FECHA    ; botón no presionado, finalizar
    
    ; botón presionado, verificar si es nueva pulsación
    lds r17, btn_estado_previo+3
    cpi r17, 1                  ; ¿estaba liberado antes?
    brne END_BTN_CHECK_FECHA    ; si no, ignorar (evitar repetición)
    
    ; nueva pulsación de decremento de mes
    ldi r17, 0                  ; actualizar estado a presionado
    sts btn_estado_previo+3, r17
    rcall DECREMENTAR_MES
    rjmp END_BTN_CHECK_FECHA
    
END_BTN_CHECK_FECHA:
    ; actualizar estado previo si el botón fue liberado
    sbrs r16, BTN_DEC_SUPERIOR  ; si el bit está a 0 (presionado), saltar
    rjmp BTN_CHECK_EXIT_FECHA   ; botón sigue presionado
    ldi r17, 1                  ; botón liberado
    sts btn_estado_previo+3, r17

BTN_CHECK_EXIT_FECHA:
    pop r18
    pop r17
    pop r16
    ret

; incrementar minutos (0-59)
INCREMENTAR_MINUTOS:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_minutos
    
    ; incrementar contador
    inc r16
    
    ; verificar límite (0-59)
    cpi r16, 60
    brlo GUAR_MINUTOS_CONTADOR
    
    ; reset a 0 si llegó a 60
    ldi r16, 0
    
GUAR_MINUTOS_CONTADOR:
    ; guardar nuevo valor
    sts contador_minutos, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_MINUTOS
    
    pop r17
    pop r16
    ret

; decrementar minutos (0-59)
DECREMENTAR_MINUTOS:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_minutos
    
    ; si ya está en 0, ir a 59
    cpi r16, 0
    brne DEC_MIN_NORMAL
    
    ldi r16, 59
    rjmp GUAR_MINUTOS_CONTADOR_DEC
    
DEC_MIN_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_MINUTOS_CONTADOR_DEC:
    ; guardar nuevo valor
    sts contador_minutos, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_MINUTOS
    
    pop r17
    pop r16
    ret

; incrementar horas (0-23)
INCREMENTAR_HORAS:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_horas
    
    ; incrementar contador
    inc r16
    
    ; verificar límite (0-23)
    cpi r16, 24
    brlo GUAR_HORAS_CONTADOR
    
    ; reset a 0 si llegó a 24
    ldi r16, 0
    
GUAR_HORAS_CONTADOR:
    ; guardar nuevo valor
    sts contador_horas, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_HORAS
    
    pop r17
    pop r16
    ret

; decrementar horas (0-23)
DECREMENTAR_HORAS:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_horas
    
    ; si ya está en 0, ir a 23
    cpi r16, 0
    brne DEC_HORA_NORMAL
    
    ldi r16, 23
    rjmp GUAR_HORAS_CONTADOR_DEC
    
DEC_HORA_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_HORAS_CONTADOR_DEC:
    ; guardar nuevo valor
    sts contador_horas, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_HORAS
    
    pop r17
    pop r16
    ret

; inicializar tabla de días por mes (1-12)
INICIAR_TABLA_DIAS:
    ldi ZH, HIGH(dias_por_mes)
    ldi ZL, LOW(dias_por_mes)
    
    ldi r16, 31        ; Enero: 31 días
    st Z+, r16
    ldi r16, 28        ; Febrero: 28 días 
    st Z+, r16
    ldi r16, 31        ; Marzo: 31 días
    st Z+, r16
    ldi r16, 30        ; Abril: 30 días
    st Z+, r16
    ldi r16, 31        ; Mayo: 31 días
    st Z+, r16
    ldi r16, 30        ; Junio: 30 días
    st Z+, r16
    ldi r16, 31        ; Julio: 31 días
    st Z+, r16
    ldi r16, 31        ; Agosto: 31 días
    st Z+, r16
    ldi r16, 30        ; Septiembre: 30 días
    st Z+, r16
    ldi r16, 31        ; Octubre: 31 días
    st Z+, r16
    ldi r16, 30        ; Noviembre: 30 días
    st Z+, r16
    ldi r16, 31        ; Diciembre: 31 días
    st Z+, r16
    
    ret

; obtener número máximo de días para el mes actual
OBTENER_DIAS_MES:
    push r17
    
    ; r16 debe contener el mes (1-12)
    dec r16                ; ajustar a índice 0-11 para acceder a la tabla
    
    ; cargar dirección de la tabla
    ldi ZH, HIGH(dias_por_mes)
    ldi ZL, LOW(dias_por_mes)
    
    ; calcular posición en la tabla
    add ZL, r16            ; sumar offset
    brcc PC+2              ; si no hay carry, saltar
    inc ZH                 ; si hay carry, incrementar ZH
    
    ; cargar valor desde la tabla
    ld r16, Z              ; r16 ahora contiene el número máximo de días
    
    pop r17
    ret

; incrementar día (1-31, dependiendo del mes)
INCREMENTAR_DIA:
    push r16
    push r17
    push r18
    
    ; obtener valor actual del día
    lds r16, contador_dia
    
    ; incrementar contador
    inc r16
    
    ; obtener límite máximo de días para el mes actual
    lds r17, contador_mes  ; cargar mes actual en r17
    mov r18, r16           ; guardar día incrementado en r18
    mov r16, r17           ; mover mes a r16 para función
    rcall OBTENER_DIAS_MES ; r16 ahora contiene días máximos
    mov r17, r16           ; días máximos en r17
    mov r16, r18           ; restaurar día incrementado en r16
    
    ; verificar si excedió el límite
    cp r16, r17
    brlo GUAR_DIA_CONTADOR ; si día < días máximos, guardar
    cp r17, r16
    breq GUAR_DIA_CONTADOR ; si día == días máximos, guardar
    
    ; reset a 1 si excedió el límite
    ldi r16, 1
    
GUAR_DIA_CONTADOR:
    ; guardar nuevo valor
    sts contador_dia, r16
    
    ; actualizar dígitos para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_DIA
    
    pop r18
    pop r17
    pop r16
    ret

; decrementar día (1-31, dependiendo del mes)
DECREMENTAR_DIA:
    push r16
    push r17
    push r18
    
    ; obtener valor actual
    lds r16, contador_dia
    
    ; si ya está en 1, ir al último día del mes
    cpi r16, 1
    brne DEC_DIA_NORMAL
    
    ; obtener número máximo de días para el mes actual
    lds r17, contador_mes  ; cargar mes actual
    mov r16, r17           ; mover mes a r16 para función
    rcall OBTENER_DIAS_MES ; r16 ahora contiene días máximos
    rjmp GUAR_DIA_CONTADOR_DEC
    
DEC_DIA_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_DIA_CONTADOR_DEC:
    ; guardar nuevo valor
    sts contador_dia, r16
    
    ; actualizar dígitos para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_DIA
    
    pop r18
    pop r17
    pop r16
    ret

; incrementar mes (1-12)
INCREMENTAR_MES:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_mes
    
    ; incrementar contador
    inc r16
    
    ; verificar límite (1-12)
    cpi r16, 13
    brlo GUAR_MES_CONTADOR
    
    ; reset a 1 si llegó a 13
    ldi r16, 1
    
GUAR_MES_CONTADOR:
    ; guardar nuevo valor
    sts contador_mes, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_MES
    
    ; verificar si el día actual es válido para el nuevo mes
    rcall AJUSTAR_DIA_A_MES
    
    pop r17
    pop r16
    ret

; decrementar mes (1-12)
DECREMENTAR_MES:
    push r16
    push r17
    
    ; obtener valor actual
    lds r16, contador_mes
    
    ; si ya está en 1, ir a 12
    cpi r16, 1
    brne DEC_MES_NORMAL
    
    ldi r16, 12
    rjmp GUAR_MES_CONTADOR_DEC
    
DEC_MES_NORMAL:
    ; decrementar normalmente
    dec r16
    
GUAR_MES_CONTADOR_DEC:
    ; guardar nuevo valor
    sts contador_mes, r16
    
    ; convertir a decenas y unidades para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_MES
    
    ; verificar si el día actual es válido para el nuevo mes
    rcall AJUSTAR_DIA_A_MES
    
    pop r17
    pop r16
    ret

; ajustar el día si excede el máximo del mes actual
AJUSTAR_DIA_A_MES:
    push r16
    push r17
    
    ; obtener días máximos para el mes actual
    lds r16, contador_mes
    rcall OBTENER_DIAS_MES  ; r16 ahora contiene días máximos
    mov r17, r16            ; días máximos en r17
    
    ; comparar con día actual
    lds r16, contador_dia
    cp r16, r17
    brlo AJUSTE_DIA_FIN     ; si día < días máximos, no ajustar
    cp r17, r16
    brne AJUSTE_DIA_MES     ; si día != días máximos, ajustar
    rjmp AJUSTE_DIA_FIN     ; si día == días máximos, no ajustar
    
AJUSTE_DIA_MES:
    ; día excede máximo, ajustar al máximo
    mov r16, r17            ; r16 = días máximos
    sts contador_dia, r16
    
    ; actualizar displays
    rcall ACTUALIZAR_DISPLAYS_DIA
    
AJUSTE_DIA_FIN:
    pop r17
    pop r16
    ret

; actualizar los displays de minutos basado en contador_minutos
ACTUALIZAR_DISPLAYS_MINUTOS:
    push r16
    push r17
    push r18
    
    ; cargar valor del contador
    lds r16, contador_minutos
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo GUAR_MIN_DIGITOS ; si es menor que 10, saltar

DECENAS_LOOP_MIN:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge DECENAS_LOOP_MIN ; si quedan más de 10, repetir
    
GUAR_MIN_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts contador_unidades_min, r16  ; guardar unidades
    sts contador_decenas_min, r17   ; guardar decenas
    
    pop r18
    pop r17
    pop r16
    ret

; actualizar los displays de horas basado en contador_horas
ACTUALIZAR_DISPLAYS_HORAS:
    push r16
    push r17
    push r18
    
    ; cargar valor del contador
    lds r16, contador_horas
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo GUAR_HORA_DIGITOS ; si es menor que 10, saltar

DECENAS_LOOP_HORA:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge DECENAS_LOOP_HORA ; si quedan más de 10, repetir
    
GUAR_HORA_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts contador_unidades_hora, r16  ; guardar unidades
    sts contador_decenas_hora, r17   ; guardar decenas
    
    pop r18
    pop r17
    pop r16
    ret

; actualizar los displays de día basado en contador_dia
ACTUALIZAR_DISPLAYS_DIA:
    push r16
    push r17
    push r18
    
    ; cargar valor del contador
    lds r16, contador_dia
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo GUAR_DIA_DIGITOS ; si es menor que 10, saltar

DECENAS_LOOP_DIA:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge DECENAS_LOOP_DIA ; si quedan más de 10, repetir
    
GUAR_DIA_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts contador_unidades_dia, r16  ; guardar unidades
    sts contador_decenas_dia, r17   ; guardar decenas
    
    pop r18
    pop r17
    pop r16
    ret

; actualizar los displays de mes basado en contador_mes
ACTUALIZAR_DISPLAYS_MES:
    push r16
    push r17
    push r18
    
    ; cargar valor del contador
    lds r16, contador_mes
    
    ; calcular decenas (r16 / 10)
    ldi r17, 0          ; inicializar decenas a 0
    cpi r16, 10         ; comparar con 10
    brlo GUAR_MES_DIGITOS ; si es menor que 10, saltar

DECENAS_LOOP_MES:
    inc r17             ; incrementar decenas
    subi r16, 10        ; restar 10
    cpi r16, 10         ; comparar si quedan más de 10
    brge DECENAS_LOOP_MES ; si quedan más de 10, repetir
    
GUAR_MES_DIGITOS:
    ; ahora r16 contiene las unidades, r17 contiene las decenas
    sts contador_unidades_mes, r16  ; guardar unidades
    sts contador_decenas_mes, r17   ; guardar decenas
    
    pop r18
    pop r17
    pop r16
    ret

; inicialización de la tabla de dígitos (patrones de 7 segmentos)
INICIAR_TABLA_DIGITOS:
    ldi ZH, HIGH(tabla_digitos)
    ldi ZL, LOW(tabla_digitos)
    
    ldi r16, 0b00111111        ; 0
    st Z+, r16
    ldi r16, 0b00000110        ; 1
    st Z+, r16
    ldi r16, 0b01011011        ; 2
    st Z+, r16
    ldi r16, 0b01001111        ; 3
    st Z+, r16
    ldi r16, 0b01100110        ; 4
    st Z+, r16
    ldi r16, 0b01101101        ; 5
    st Z+, r16
    ldi r16, 0b01111101        ; 6
    st Z+, r16
    ldi r16, 0b00000111        ; 7
    st Z+, r16
    ldi r16, 0b01111111        ; 8
    st Z+, r16
    ldi r16, 0b01101111        ; 9
    st Z+, r16
    
    ret

; rutina para mostrar los dígitos en los displays según modo actual
MOSTRAR_DISPLAYS:
    ; verificar estado del sistema para determinar qué mostrar
    lds r17, estado_sistema
    
    cpi r17, ESTADO_RELOJ
    breq MOSTRAR_RELOJ_NORMAL
    
    cpi r17, ESTADO_EDICION_RELOJ
    breq MOSTRAR_RELOJ_EDICION
    
    cpi r17, ESTADO_FECHA
    breq MOSTRAR_FECHA_NORMAL
    
    cpi r17, ESTADO_EDICION_FECHA
    breq MOSTRAR_FECHA_EDICION
    
    cpi r17, ESTADO_EDICION_ALARMA
    breq MOSTRAR_ALARMA_EDICION
    
    ; si no coincide con ningún estado, mostrar reloj por defecto
    rjmp MOSTRAR_RELOJ_NORMAL
    
MOSTRAR_RELOJ_NORMAL:
    ; en modo reloj normal, siempre mostrar los displays
    rcall MOSTRAR_RELOJ
    ret
    
MOSTRAR_RELOJ_EDICION:
    ; en modo edición de reloj, verificar estado del LED para decidir si mostrar
    lds r16, estado_led
    cpi r16, 0           ; si estado_led es 0 (apagado), no mostrar displays
    breq NO_MOSTRAR_DISPLAYS
    
    ; mostrar reloj en modo edición
    rcall MOSTRAR_RELOJ
    ret
    
MOSTRAR_FECHA_NORMAL:
    ; en modo fecha normal, siempre mostrar los displays
    rcall MOSTRAR_FECHA
    ret
    
MOSTRAR_FECHA_EDICION:
    ; en modo edición de fecha, verificar estado del LED para decidir si mostrar
    lds r16, estado_led
    cpi r16, 0           ; si estado_led es 0 (apagado), no mostrar displays
    breq NO_MOSTRAR_DISPLAYS
    
    ; mostrar fecha en modo edición
    rcall MOSTRAR_FECHA
    ret
    
MOSTRAR_ALARMA_EDICION:
    ; en modo edición de alarma, verificar estado del LED para decidir si mostrar
    lds r16, estado_led
    cpi r16, 0           ; si estado_led es 0 (apagado), no mostrar displays
    breq NO_MOSTRAR_DISPLAYS
    
    ; mostrar alarma en modo edición
    rcall MOSTRAR_ALARMA
    ret
    
NO_MOSTRAR_DISPLAYS:
    ; asegurarse de que todos los displays estén apagados cuando el LED está apagado
    rcall APAGAR_TODOS_DISPLAYS
    ret

; mostrar reloj (horas:minutos)
MOSTRAR_RELOJ:
    ; mostrar unidades de minutos
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_unidades_min
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES      ; activar display de unidades
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de minutos
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_decenas_min
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS       ; activar display de decenas
    rcall DELAY_MULTIPLEX
    
    ; mostrar unidades de hora
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_unidades_hora
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES_SUPERIOR ; activar display de unidades hora
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de hora
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_decenas_hora
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS_SUPERIOR  ; activar display de decenas hora
    rcall DELAY_MULTIPLEX
    
    ret

; mostrar fecha (día:mes)
MOSTRAR_FECHA:
    ; mostrar unidades de día
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_unidades_dia
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES      ; activar display de unidades día
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de día
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_decenas_dia
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS       ; activar display de decenas día
    rcall DELAY_MULTIPLEX
    
    ; mostrar unidades de mes
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_unidades_mes
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES_SUPERIOR ; activar display de unidades mes
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de mes
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, contador_decenas_mes
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS_SUPERIOR  ; activar display de decenas mes
    rcall DELAY_MULTIPLEX
    
    ret

; mostrar alarma (horas:minutos)
MOSTRAR_ALARMA:
    ; mostrar unidades de minutos de alarma
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, alarma_unidades_min
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES      ; activar display de unidades
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de minutos de alarma
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, alarma_decenas_min
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS       ; activar display de decenas
    rcall DELAY_MULTIPLEX
    
    ; mostrar unidades de hora de alarma
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, alarma_unidades_hora
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_UNIDADES_SUPERIOR ; activar display de unidades hora
    rcall DELAY_MULTIPLEX
    
    ; mostrar decenas de hora de alarma
    rcall APAGAR_TODOS_DISPLAYS
    lds r16, alarma_decenas_hora
    rcall OBTENER_PATRON
    out PORTD, r16                   ; cargar patrón de segmentos
    sbi PORTC, DISPLAY_DECENAS_SUPERIOR  ; activar display de decenas hora
    rcall DELAY_MULTIPLEX
    
    ret

; apagar todos los displays
APAGAR_TODOS_DISPLAYS:
    cbi PORTC, DISPLAY_UNIDADES
    cbi PORTC, DISPLAY_DECENAS
    cbi PORTC, DISPLAY_UNIDADES_SUPERIOR
    cbi PORTC, DISPLAY_DECENAS_SUPERIOR
    ret

; obtener patrón de 7 segmentos para un dígito
OBTENER_PATRON:
    ldi ZH, HIGH(tabla_digitos)
    ldi ZL, LOW(tabla_digitos)
    add ZL, r16                ; sumar offset
    brcc PC+2                  ; si no hay carry, saltar
    inc ZH                     ; si hay carry, incrementar ZH
    ld r16, Z                  ; cargar patrón desde la tabla
    ret

; pequeño retardo para el multiplexado
DELAY_MULTIPLEX:
    ldi r17, 50
DELAY_LOOP:
    dec r17
    brne DELAY_LOOP
    ret

; actualiza el estado del LED y displays según el modo actual
ACTUALIZAR_LED:
    ; verificar el estado actual del sistema
    lds r18, estado_sistema
    
    ; comportamiento según modo actual
    cpi r18, ESTADO_EDICION_RELOJ
    breq MODO_EDICION
    
    cpi r18, ESTADO_EDICION_FECHA
    breq MODO_EDICION
    
    cpi r18, ESTADO_EDICION_ALARMA
    breq MODO_EDICION
    
    ; en modo normal (reloj o fecha): LED parpadea, displays siempre encendidos
    lds r16, estado_led
    cpi r16, 0                 ; verificar si el LED está apagado
    breq ENCENDER_LED_NORMAL
    
    ; apagar solo el LED en modo normal
    cbi PORTC, LED_INDICADOR
    ldi r16, 0
    sts estado_led, r16
    ret
    
ENCENDER_LED_NORMAL:
    ; encender solo el LED en modo normal
    sbi PORTC, LED_INDICADOR
    ldi r16, 1
    sts estado_led, r16
    ret
    
MODO_EDICION:
    ; en modo edición: LED y displays parpadean juntos
    lds r16, estado_led
    cpi r16, 0                 ; verificar si el LED está apagado
    breq ENCENDER_LED_EDICION
    
    ; apagar LED y establecer displays como apagados
    cbi PORTC, LED_INDICADOR
    ldi r16, 0
    sts estado_led, r16
    ret
    
ENCENDER_LED_EDICION:
    ; encender LED y establecer displays como encendidos
    sbi PORTC, LED_INDICADOR
    ldi r16, 1
    sts estado_led, r16
    ret

; rutina de interrupción del Timer0
TIMER0_OVF:
    push r16
    push r17
    push r18
    in r17, SREG
    push r17
    
    ; manejar el contador para el parpadeo del LED (cada 500ms)
    lds r16, contador_parpadeo
    inc r16
    cpi r16, 30                ; aproximadamente 500ms (30 desbordamientos)
    brne CHECK_SEGUNDO         ; si no han pasado 500ms, saltar a verificar segundos
    
    ; ha pasado medio segundo, alternar estado del LED
    ldi r16, 0                 ; reiniciar contador de parpadeo
    sts contador_parpadeo, r16
    
    ; verificar en qué estado estamos para determinar tipo de parpadeo
    rcall ACTUALIZAR_LED       ; alternar estado del LED y displays según modo
    
CHECK_SEGUNDO:
    sts contador_parpadeo, r16
    
    ; verificar estado del sistema - solo no contar si estamos en edición DE RELOJ O FECHA
    lds r18, estado_sistema
    cpi r18, ESTADO_EDICION_RELOJ
    breq SALIR_TIMER           ; si estamos en modo edición de reloj, no contar segundos
    
    cpi r18, ESTADO_EDICION_FECHA
    breq SALIR_TIMER           ; si estamos en modo edición de fecha, no contar segundos
    
    ; Eliminamos la comprobación de ESTADO_EDICION_ALARMA para que el reloj siga contando
    ; incluso cuando estamos programando la alarma
    
    ; verificar si la alarma está sonando para incrementar su contador
    lds r18, alarma_sonando
    cpi r18, 1
    brne CONTINUAR_TIMER       ; si la alarma no está sonando, continuar
    
    ; la alarma está sonando, incrementar su contador (una vez por segundo)
    lds r16, contador_timer
    cpi r16, 61                ; verificar si ha pasado un segundo completo
    brne CONTINUAR_TIMER       ; si no ha pasado un segundo, no incrementar
    
    ; ha pasado un segundo, incrementar contador de alarma
    lds r18, contador_alarma
    inc r18
    sts contador_alarma, r18
    
CONTINUAR_TIMER:
    ; contar segundos incluso en modo fecha y alarma (cuenta en segundo plano)
    ; incrementar contador para medir 1 segundo
    lds r16, contador_timer
    inc r16
    
    ; verificar si ha pasado 1 segundo (aprox. 61 desbordamientos con preescalador 1024)
    cpi r16, 61
    brne GUARDAR_TIMER         ; si no han pasado 61 desbordamientos, guardar y salir
    
    ; ha pasado 1 segundo
    ldi r16, 0                 ; reiniciar contador del timer
    sts contador_timer, r16
    
    ; incrementar contador de segundos
    lds r16, contador_segundos
    inc r16
    
    ; verificar si han pasado 60 segundos
    cpi r16, 60
    brne GUARDAR_SEGUNDOS      ; si no han pasado 60 segundos, guardar y salir
    
    ; ha pasado 1 minuto completo
    ldi r16, 0                 ; reiniciar contador de segundos
    sts contador_segundos, r16
    
    ; incrementar minutos y verificar cambio de día
    rcall INCREMENTAR_TIEMPO_AUTO
    
    ; verificar si coincide con la hora de alarma
    rcall VERIFICAR_ALARMA
    
    rjmp SALIR_TIMER
    
GUARDAR_SEGUNDOS:
    sts contador_segundos, r16
    rjmp SALIR_TIMER
    
GUARDAR_TIMER:
    sts contador_timer, r16
    
SALIR_TIMER:
    pop r17
    out SREG, r17
    pop r18
    pop r17
    pop r16
    reti

; verificar si la hora actual coincide con la hora de alarma
VERIFICAR_ALARMA:
    push r16
    push r17
    
    ; verificar si la alarma está activa
    lds r16, alarma_activa
    cpi r16, 0
    breq SALIR_VERIFICAR_ALARMA_HORA  ; si la alarma no está activa, salir
    
    ; verificar si la alarma ya está sonando
    lds r16, alarma_sonando
    cpi r16, 1
    breq SALIR_VERIFICAR_ALARMA_HORA  ; si ya está sonando, salir
    
    ; comparar horas
    lds r16, contador_horas
    lds r17, alarma_horas
    cp r16, r17
    brne SALIR_VERIFICAR_ALARMA_HORA  ; si las horas no coinciden, salir
    
    ; comparar minutos
    lds r16, contador_minutos
    lds r17, alarma_minutos
    cp r16, r17
    brne SALIR_VERIFICAR_ALARMA_HORA  ; si los minutos no coinciden, salir
    
    ; la hora actual coincide con la hora de alarma, activar alarma
    ldi r16, 1
    sts alarma_sonando, r16    ; indicar que la alarma está sonando
    
    ; inicializar contador de tiempo de alarma
    ldi r16, 0
    sts contador_alarma, r16
    
    ; activar pin de alarma en PC0
    sbi PORTC, PIN_ALARMA
    
SALIR_VERIFICAR_ALARMA_HORA:
    pop r17
    pop r16
    ret

; incrementar automáticamente los minutos (modo reloj) y verificar cambio de día
INCREMENTAR_TIEMPO_AUTO:
    push r16
    push r17
    push r18
    
    ; cargar el valor actual del contador de minutos
    lds r16, contador_minutos
    
    ; incrementar el contador de minutos
    inc r16
    cpi r16, 60              ; verificar si llegó a 60
    brne GUARDAR_MIN_AUTO_T
    
    ; si llegó a 60, reiniciar a 0 y aumentar una hora
    ldi r16, 0
    sts contador_minutos, r16
    
    ; incrementar una hora
    lds r16, contador_horas
    inc r16
    cpi r16, 24              ; verificar si llegó a 24 horas
    brne GUARDAR_HORA_AUTO_T
    
    ; si llegó a 24 horas (medianoche), reiniciar a 0 y avanzar un día
    ldi r16, 0
    sts contador_horas, r16
    
    ; incrementar fecha al cambiar de día
    rcall AVANZAR_DIA_AUTO
    
GUARDAR_HORA_AUTO_T:
    sts contador_horas, r16
    
    ; actualizar displays de horas
    rcall ACTUALIZAR_DISPLAYS_HORAS
    
    ; continuar con la actualización de minutos
    ldi r16, 0               ; minutos = 0 (si venimos de incrementar horas)
    cpi r16, 60              ; verificar si incrementamos horas
    brne GUARDAR_MIN_ORIGINAL ; si no incrementamos horas, mantener el valor original
    
GUARDAR_MIN_AUTO_T:
    sts contador_minutos, r16
    
    ; actualizar displays de minutos
    rcall ACTUALIZAR_DISPLAYS_MINUTOS
    
    pop r18
    pop r17
    pop r16
    ret
    
GUARDAR_MIN_ORIGINAL:
    lds r16, contador_minutos  ; restaurar valor original de minutos
    rjmp GUARDAR_MIN_AUTO_T

; incrementar automáticamente el día al cambiar de día (medianoche)
AVANZAR_DIA_AUTO:
    push r16
    push r17
    push r18
    
    ; obtener valor actual del día
    lds r16, contador_dia
    
    ; incrementar contador
    inc r16
    
    ; obtener límite máximo de días para el mes actual
    lds r17, contador_mes     ; cargar mes actual en r17
    mov r18, r16              ; guardar día incrementado en r18
    mov r16, r17              ; mover mes a r16 para función
    rcall OBTENER_DIAS_MES    ; r16 ahora contiene días máximos
    mov r17, r16              ; días máximos en r17
    mov r16, r18              ; restaurar día incrementado en r16
    
    ; verificar si excedió el límite
    cp r16, r17
    brlo DIA_AUTO_NORMAL      ; si día < días máximos, guardar
    cp r17, r16
    breq DIA_AUTO_NORMAL      ; si día == días máximos, guardar
    
    ; si excedió el límite, reset a día 1 e incrementar mes
    ldi r16, 1
    sts contador_dia, r16
    
    ; incrementar mes
    lds r16, contador_mes
    inc r16
    
    ; verificar límite de mes (1-12)
    cpi r16, 13
    brlo MES_AUTO_NORMAL
    
    ; si llegó a 13, volver a mes 1 (enero)
    ldi r16, 1
    
MES_AUTO_NORMAL:
    sts contador_mes, r16
    
    ; actualizar displays de mes
    rcall ACTUALIZAR_DISPLAYS_MES
    
    ; actualizar displays de día (siempre, incluso si no cambió el día)
    rcall ACTUALIZAR_DISPLAYS_DIA
    rjmp FIN_DIA_AUTO
    
DIA_AUTO_NORMAL:
    sts contador_dia, r16
    
    ; actualizar dígitos para mostrar en display
    rcall ACTUALIZAR_DISPLAYS_DIA

FIN_DIA_AUTO:
    pop r18
    pop r17
    pop r16
    ret