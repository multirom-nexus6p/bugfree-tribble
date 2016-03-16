# Python 3 please
# see https://android.googlesource.com/platform/external/libselinux/+/master/utils/sefcontext_compile.c
import sys

def u32(b, i):
	return b[i] | b[i+1] << 8 | b[i+2] << 16 | b[i+3] << 24

with open(sys.argv[1], "rb") as infile:
	d = infile.read()
if True:
	i = 8
	pcrelen = u32(d, i)
	i += 4 + pcrelen
	stems = u32(d, i)
	i += 4
	stemlist = [None]*stems
	for stem in range(stems):
		stemlen = u32(d, i)
		i += 4
		stemstr = d[i:i+stemlen].decode("utf-8")
		i += stemlen + 1
		stemlist[stem] = stemstr
	regexes = u32(d, i)
	i += 4
	for r in range(regexes):
		contextlen = u32(d, i)
		i += 4
		context = d[i:i+contextlen-1].decode("utf-8")
		i += contextlen
		origregexlen = u32(d, i)
		i += 4
		origregex = d[i:i+origregexlen-1].decode("utf-8")
		i += origregexlen
		# mode bits
		i += 4
		stemid = u32(d, i)
		i += 4
		# meta
		i += 4
		# specs prefix_len
		i += 4
		pcrelen = u32(d, i)
		i += 4 + pcrelen
		pcrestudylen = u32(d, i)
		i += 4 + pcrestudylen
		print(origregex, context)
