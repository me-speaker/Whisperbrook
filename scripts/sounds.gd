extends AudioStreamPlayer

func note(freq: float, seconds: float, bell: bool=false) -> void:
	var rate:=22050
	var count:=int(rate*seconds)
	var bytes:=PackedByteArray()
	bytes.resize(count*2)
	for i in count:
		var t:=float(i)/rate
		var wave:=sin(TAU*freq*t)
		if bell: wave+=0.45*sin(TAU*freq*2.41*t)*exp(-10*t)
		var sample_value:=wave*exp(-4*t/seconds)*minf(1,t*90.0)
		bytes.encode_s16(i*2,int(sample_value*5200))
	var stream_data:=AudioStreamWAV.new()
	stream_data.format=AudioStreamWAV.FORMAT_16_BITS
	stream_data.mix_rate=rate
	stream_data.data=bytes
	stream=stream_data
	play()
