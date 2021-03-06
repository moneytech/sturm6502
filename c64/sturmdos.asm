; SturmDOS
; Jul 23 2017, Initial version (including load program, reading error channel)
; Jul 24 2017, Reading directory, sending a command via the command channel
; Jul 25 2017, Changing default drive
;
; Supported commands:
;
; /"program"	Load basic program
; <-"program"	Load and run basic program (*)
; %"program"	Load machine language program
;
; @		Read error channel
; @$		Read directory
; @#x		Change default drive x=8-32
; @Q		Uninstall SturmDOS
;
; @"N:disk name,identifier"	Format a disk (New)
; @"S:file"			Delete a file (Scratch)
; @"R:new name=old name"	Rename a file
; @"I"				Initialize (i.e. reset) the drive
; @"V"				Validate the disk (i.e. disk doctor)
; @"C:new file=old file"	Copy a file
; @"CD directory"		Change a directory (for example supported by sd2iec)
; @"CD <-"			Change to the above directory (sd2iec) (*)
;
;				(*) = <- means left arrow

; kernal routines
chkin	=	$ffc6
chkout	=	$ffc9
chrin	=	$ffcf
chrout	=	$ffd2
close	=	$ffc3
clrchn	=	$ffcc
load	=	$ffd5
open	=	$ffc0
readst	=	$ffb7
setlfs	=	$ffba
setnam	=	$ffbd

basic	=	$2b
variables =	$2d
chrget	=	$73
textptr	=	$7a
endofload =	$ae
devnbr	=	$ba
ndx	=	$c6	; number of chars in keyboard buffer
buffer	=	$200
keybuffer =	$277
warm	=	$302
igone	=	$308
goneptr	=	$3fc
saveptr	=	$3fe
tape	=	$33c	; tape buffer
device	=	tape
secondary =	tape+1
run	=	tape+2
length	=	tape+3
bin	=	tape+4
bcd	=	tape+6
param	=	tape+9

; macros

.if 0
	MAC	lbeq
	dc.b	$d0,$3	; bne +3
	jmp	{1}
	ENDM
.endif

.mac	lbeq
	.byte	$d0,$3	; bne +3
	jmp	\1	
.endmac

	.org	$c000-2
	.word	$c000

; install dos commands
;
; add own routine to igone vector
; igone will point to own routine
;
; after our own routine we will jump
; to gone+3
	lda	igone
	sta	goneptr
	sta	saveptr
	lda	igone+1
	sta	goneptr+1
	sta	saveptr+1
	clc
	lda	#3
	adc	goneptr
	sta	goneptr
	lda	#0
	adc	goneptr+1
	sta	goneptr+1
	lda	#<checkCommand
	sta	igone
	lda	#>checkCommand
	sta	igone+1

	; print title string
	ldx	#<title
	ldy	#>title
	jsr	printString
	
	; set default device number
	lda	devnbr
	bne	install1
	lda	#8
install1
	sta	device
	rts

; check commands
checkCommand
	jsr	chrget
	php
	cmp	#"@"
	lbeq	atcommand
	cmp	#$ad	; / basic token
	 lbeq	loadBasic
	cmp	#"%"
	lbeq	loadML
	cmp	#$5f	; left arrow
	lbeq	runBasic
	plp
	jmp	(goneptr)

; process @ command
atcommand
	plp
	jsr	parseString
	lda	length
	lbeq	readError
	lda	param
	cmp	#"q"
	beq	quit
	cmp	#"$"
	lbeq	readDir
	cmp	#"#"
	lbeq	changeDrive
	; jump to send command routine if it is not @, @$, or @# command
	jmp	sendCommand

; parse parameter string
;
; routine supresses leading space and " characters
; routine supresses trailing " character
parseString
	jsr	@nextChar	; supress spaces
	cmp	#" "
	beq	parseString
	ldx	#0
	cmp	#'"'
	bne	@parseString3
@parseString2
	jsr	@nextChar	; supress "
@parseString3
	cmp	#'"'
	beq	@parseExit1
	cmp	#0
	beq	@parseExit2
	sta	param,x
	inx
	sec
	bcs	@parseString2
@parseExit1
	jsr	@nextChar	; supress "
@parseExit2
	stx	length
;debug
;	ldx	#0
;	ldy	length
;	beq	parseExit3
;debugPrint
;	lda	param,x
;	jsr	chrout
;	inx
;	dey
;	bne	debugPrint
;	lda	#13
;	jsr	chrout
;parseExit3
	rts

; get next character in parameter string
@nextChar
	ldy	#0
	inc	textptr
	bne	@nextChar2
	inc	textptr+2
@nextChar2
	lda	(textptr),y
	rts
; remove dos commands from basic interpreter
quit	lda	saveptr
	sta	igone
	lda	saveptr+1
	sta	igone+1
	lda	#0
	jmp	(goneptr)

; load and run basic program
runBasic
	lda	#$80
	sta	run
	sec
	bcs	loadBasic2

; load basic program
loadBasic
	lda	#0
	sta	run
loadBasic2
	ldx	#0
	stx	secondary
	sec
	bcs	loadFile

; load machine language program
loadML	lda	#0
	sta	run
	ldx	#1
	stx	secondary

; general load file routine
loadFile
	plp

	jsr	parseString

	lda	#1	; logical file number
	ldx	device
	ldy	secondary
	jsr	setlfs

	ldx	#<param
	ldy	#>param
	lda	length
	jsr	setnam

	lda	#0	; load
	ldx	basic
	ldy	basic+1
	jsr	load

	; set start of variables (needed in case of basic program)
	stx	variables
	sty	variables+1

	; print ready after loading
	ldx	#<readytext
	ldy	#>readytext
	jsr	printString

	; insert run command to the keyboard buffer if needed
	lda	run
	beq	loadFile2
	ldx	#0
@copyRunCmd
	lda	runtext,x
	sta	keybuffer,x
	inx
	cmp	#13
	bne	@copyRunCmd
	stx	ndx
loadFile2
	jmp	(warm)	; basic warm start

; open error channel
;
openCommandChannel
	lda	#15	; logical file
	ldx	device	; device number
	ldy	#15	; command channel
	jsr	setlfs

	lda	#0	; length of name
	jsr	setnam

	jsr	open
	bcs	openCommandExit
	rts

openCommandExit
	; file must be also closed when opening fails
	lda	#15	
	jsr	close
	lda	#0
	jmp	(goneptr)

; send command to a drive
;
sendCommand
	; check that command's length >0
	; this is probably redundant check
	ldy	length
	beq	sendCommandExit

	lda	#15
	ldx	device
	ldy	#15
	jsr	setlfs

	lda	length
	ldx	#<param
	ldy	#>param
	jsr	setnam

	jsr	open
	sec
	bcs	openCommandExit

sendCommandExit
	lda	#0
	jmp	(goneptr)

; read a string from error channel and print it
;
readError
	jsr	openCommandChannel

	ldx	#15	; logical file
	jsr	chkin

@prtErr	jsr	chrin
	cmp	#13
	beq	@preadError2
	jsr	chrout
	jmp	@prtErr
@preadError2
	jsr	chrout
	;lda	#5
	lda	#15
	jsr	close
	jsr	clrchn	
@preadErrorExit
	lda	#0
	jmp	(goneptr)

; Change default drive
;
changeDrive
	lda	param+1
	sec
	sbc	#"0"
	sta	device
	lda	length
	cmp	#2
	beq	@changeDrive1
	lda	param+2
	cmp	#"0"
	bcc	@changeDrive1
	cmp	#":"
	bcs	@changeDrive1
	sec
	sbc	#"0"
	pha
	lda	device
	asl
	asl
	clc
	adc	device	
	asl
	sta	device	; device = (device * 2 * 2 + device) * 2
	pla
	clc
	adc	device
	sta	device
@changeDrive1
	lda	#0
	jmp	(goneptr)
	
	
; general print string routine
; x=address (low byte)
; y=address (high byte)
; changes a, x and flags
printString
	stx	@printString2+1
	sty	@printString2+2
	ldx	#0
@printString2
	lda	readytext,x
	beq	@printExit
	jsr	chrout
	inx
	sec
	bcs	@printString2
@printExit
	rts

readDir
	lda	#1	; logical file
	ldx	device	; device number
	ldy	#0	; command
	jsr	setlfs

	lda	#1	; length of name
	ldx	#<dirname
	ldy	#>dirname
	jsr	setnam

	jsr	open
	bcs	@preadDirError
	;jsr	readst
	;and	#$ff
	;bne	readDirError

	ldx	#1	; logical file
	jsr	chkin

	jsr	chrin	; skip start address
	jsr	chrin

@preadDir1
	jsr	chrin	; skip 16-bit link to next basic line
	jsr	chrin

	jsr	readst
	and	#$ff
	bne	@preadDirExit ; brach to exit if there was an error

	jsr	chrin	; read basic line number
	sta	bin
	jsr	chrin
	sta	bin+1

; convert basic line number to bcd
	jsr	binBCD16
; print line number
	jsr	printLineNum

; print characters until end of line is reached
@preadDir2
	jsr	chrin
	cmp	#0
	beq	@preadDirEOL
	jsr	chrout
	jmp	@preadDir2

; print return at the end of line
@preadDirEOL
	lda	#13
	jsr	chrout
	jmp	@preadDir1

@preadDirExit
	lda	#1
	jsr	close
	jsr	clrchn

@preadDirError
	lda	#1	; open failed, but file must be still closed
	jsr	close
	lda	#0
	jmp	(goneptr)

;
; print 16-bit line number
;

; suppress leading zeroes
printLineNum
	lda	bcd+2
	and	#$0f
	bne	@lineNum1
	lda	bcd+1
	and	#$f0
	bne	@lineNum2
	lda	bcd+1
	and	#$0f
	bne	@lineNum3
	lda	bcd+0
	and	#$f0
	bne	@lineNum4
	jmp	@lineNum5
; print x0000
@lineNum1
	ora	#48	; convert to petscii
	jsr	chrout
; print x000
@lineNum2
	ror
	ror
	ror
	ror
	and	#$0f
	ora	#48
	jsr	chrout
; print x00
@lineNum3
	ora	#48
	jsr	chrout
; print x0
@lineNum4
	ror
	ror
	ror
	ror
	and	#$0f
	ora	#48
	jsr	chrout
; print x
@lineNum5
	lda	bcd+0
	and	#$0f
	ora	#48
	jsr	chrout
; print extra space
	lda	#32
	jsr	chrout
	rts
			
; convert 16-bit value to bcd
;
binBCD16
	sed		; Switch to decimal mode
	lda #0		; Ensure the result is clear
	sta bcd+0
	sta bcd+1
	sta bcd+2
	ldx #16		; The number of source bits

@convertBit
	asl bin+0	; Shift out one bit
	rol bin+1
	lda bcd+0	; And add into result
	adc bcd+0
	sta bcd+0
	lda bcd+1	; propagating any carry
	adc bcd+1
	sta bcd+1
	lda bcd+2	; ... thru whole result
	adc bcd+2
	sta bcd+2
	dex		; And repeat for next bit
	bne @convertBit
	cld		; Back to binary

	rts		; All Done.

title	.byte	"sturmdos v1.0 installed",13,0
runtext	.byte	"run",13,0	; run command
readytext .byte	13,"ready.",13,0
dirname	.byte	"$"
