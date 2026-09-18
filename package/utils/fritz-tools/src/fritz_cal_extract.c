/*
 * A tool for reading the zlib compressed calibration data
 * found in AVM Fritz!Box based devices).
 *
 * Copyright (c) 2017 Christian Lamparter <chunkeey@googlemail.com>
 *
 * Based on zpipe, which is an example of proper use of zlib's inflate().
 * that is Not copyrighted -- provided to the public domain
 * Version 1.4  11 December 2005  Mark Adler
 *
 * Modifications to also handle calibration data in reversed byte order
 * (c) 2024 by <dzsoftware@posteo.org>.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <endian.h>
#include <errno.h>
#include "zlib.h"

#define CHUNK 1024
#define DEFAULT_BUFFERSIZE (129 * 1024)

/* window the -t scan reads the input with; only 1 byte of it is carried over */
#define SCAN_CHUNK (64 * 1024)

/*
 * The records are AVM's "prom_config" entries, whose on-disk header is defined
 * in the GPL drops at
 *   drivers/char/avm_new/include/uapi/avm/enh/prom_uapi.h:43-59
 *
 *	struct avm_prom_config_hdr_head { __u8 version; __u8 type; };
 *	struct avm_prom_config_hdr    { head; __be16 len; };			v1, v2
 *	struct avm_prom_config_hdr_v3 { head; __be16 cal_options; __be32 len; };	v3
 *
 * len is the length of the payload as stored, i.e. the compressed length for a
 * zlib record. version 0xff is erased flash, which is how the record area ends;
 * type is enum avm_prom_config_type and has to be below AVM_PROM_MAX_TYPE.
 * The reader is avm_prom_load_config_entry(), prom_config.c:517-581.
 *
 * -e matches the first two header bytes as one big-endian 16-bit number, which
 * is what this tool has always done; -t matches the type alone, the way AVM's
 * own reader does, and is what makes a scan possible.
 */
#define PROM_MAX_TYPE		27
#define PROM_HDR_V2_SIZE	4
#define PROM_HDR_V3_SIZE	8

#define MIN(a,b) (((a)<(b))?(a):(b))

/* extract_payload() results */
enum extract_result {
	EXTRACT_OK = 0,
	EXTRACT_TRUNCATED,	/* stream did not end and we needed all of it */
	EXTRACT_ZLIB,		/* zlib refused the stream; *zret says why */
	EXTRACT_SHORT,		/* less data came out than -i wants to skip */
	EXTRACT_DECLARED_LEN,	/* stream is not exactly the declared length */
	EXTRACT_CHECKSUM,	/* -c: the blob failed its own checksum */
	EXTRACT_NOT_FOUND,	/* -t: no record of that type in the input */
};

struct extract_opts {
	size_t limit;		/* -l, 0 = not given */
	size_t skip;		/* -i */
	bool reversed;		/* -r */
	bool check;		/* -c */
};

/* Reverse byte order in data buffer.
 * 'top' is position of last valid data byte = (datasize - 1)
 */
static void buffer_reverse(unsigned char *data, unsigned int top)
{
	register unsigned char swapbyte;
	const unsigned int center = top / 2;

	for (unsigned int bottom = 0; bottom < center; ++bottom, --top) {
		swapbyte = data[bottom];
		data[bottom] = data[top];
		data[top] = swapbyte;
	}
}

/* Decompress from file source to data buffer until stream ends
 * or *limit bytes have been written to buffer.
 *
 * On call, 'limit' must reference a variable containing the intended
 * number of bytes to retrieve (must be <= allocated buffer size).
 *
 * 'consumed', if not NULL, receives the number of compressed bytes inflate()
 * took off the stream — for a complete stream that is the record's stored
 * length, which is what lets the caller check a candidate against its header.
 *
 * Return values (success):
 * Z_END_STREAM if complete data was retrieved (*limit == size of complete data),
 * or Z_OK if data was retrieved up to limit (*limit == original value).
 *
 * Return values (failure):
 * Z_MEM_ERROR if memory could not be allocated for processing,
 * Z_DATA_ERROR if the deflate data is invalid or incomplete,
 * Z_VERSION_ERROR if the version of zlib.h and the version of the
 * library linked do not match, or
 * Z_ERRNO if there is an error reading or writing the files.
 */
static int inflate_to_buffer(FILE *source, unsigned char *buf, size_t *limit,
			     size_t *consumed)
{
	int ret;
	z_stream strm;
	unsigned char in[CHUNK];

	/* allocate inflate state */
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.avail_in = 0;
	strm.next_in = Z_NULL;
	ret = inflateInit(&strm);
	if (ret != Z_OK)
		return ret;

	/* set data buffer as stream output */
	strm.avail_out = *limit;
	strm.next_out = buf;

	/* decompress until deflate stream ends or end of file */
	do {
		strm.avail_in = fread(in, 1, CHUNK, source);
		if (ferror(source)) {
			(void)inflateEnd(&strm);
			return Z_ERRNO;
		}
		if (strm.avail_in == 0)
			break;
		strm.next_in = in;

		/* run inflate(), fill data buffer with all available output */
		ret = inflate(&strm, Z_FINISH);
		assert(ret != Z_STREAM_ERROR);  /* state not clobbered */

		switch (ret) {
			case Z_NEED_DICT:
				ret = Z_DATA_ERROR;     /* and fall through */
			case Z_DATA_ERROR:
			case Z_MEM_ERROR:
				(void)inflateEnd(&strm);
				return ret;
		}
		/* done when inflate() says it's done or limit reached */
	} while (ret != Z_STREAM_END && strm.avail_out > 0);

	/* set limit to end of retrieved data */
	assert(strm.total_out <= *limit);
	*limit = strm.total_out;
	if (consumed)
		*consumed = strm.total_in;

	/* clean up and return */
	(void)inflateEnd(&strm);
	return (ret == Z_STREAM_END ? Z_STREAM_END : (strm.avail_out == 0 ? Z_OK : Z_DATA_ERROR));
}

/* report a zlib or i/o error */
static void zerr(int ret)
{
	switch (ret) {
	case Z_ERRNO:
		if (ferror(stdin))
			fputs("error reading stdin\n", stderr);
		if (ferror(stdout))
			fputs("error writing stdout\n", stderr);
		break;
	case Z_STREAM_ERROR:
		fputs("invalid compression level\n", stderr);
		break;
	case Z_DATA_ERROR:
		fputs("invalid or incomplete deflate data\n", stderr);
		break;
	case Z_MEM_ERROR:
		fputs("out of memory\n", stderr);
		break;
	case Z_VERSION_ERROR:
		fputs("zlib version mismatch!\n", stderr);
	}
}

static unsigned int get_num(char *str)
{
	if (!strncmp("0x", str, 2))
		return strtoul(str+2, NULL, 16);
	else
		return strtoul(str, NULL, 10);
}

static void usage(void)
{
	fprintf(stderr, "Usage: fritz_cal_extract {-e entry_id | -t prom_type}\n"
			"\t[-s seek offset] [-l limit] [-c verify blob checksum]\n"
			"\t[-r reverse extracted data] [-i skip n bytes] [-o output file] [infile]\n"
			"Finds and extracts zlib compressed calibration data in the EVA loader\n"
			"\n"
			"-e walks the record chain from -s and matches the first two header\n"
			"   bytes as one big-endian 16-bit value, e.g. -e 0x207 for version 2,\n"
			"   type 7. It needs -s to name the exact record: AVM leaves 0xff fill\n"
			"   between records and the walk cannot cross it.\n"
			"-t scans the whole input for a record of that prom_config type (7 is\n"
			"   the first radio's calibration, 8 the second's) and needs no offset.\n"
			"   A candidate counts only if its payload is a complete zlib stream of\n"
			"   exactly the length its header declares, so the scan can tell a real\n"
			"   record from the header-shaped bytes in the bootloader code around it.\n"
			"   A record that inflates to more than 129 KiB is out of its reach.\n"
			"-c additionally requires the extracted blob to pass the 16-bit\n"
			"   ones-complement checksum it carries at offset 2, and takes the\n"
			"   output length from the blob's own length field at offset 0 when no\n"
			"   -l is given. It applies after -i, i.e. to the bytes about to be\n"
			"   written. AVM's ath10k blobs carry it; an ath9k EEPROM does not.\n");
	exit(EXIT_FAILURE);
}

struct cal_entry {
	uint16_t id;
	uint16_t len;
} __attribute__((packed));

/*
 * Read a prom_config header at the current stream position, leaving the
 * stream on the payload. Returns 0 and fills *len for a header AVM's reader
 * would accept, -1 otherwise — which covers the 0xff of erased flash as well
 * as anything malformed.
 */
static int prom_read_hdr(FILE *in, size_t *len)
{
	unsigned char hdr[PROM_HDR_V3_SIZE];
	size_t rest = PROM_HDR_V3_SIZE - PROM_HDR_V2_SIZE;

	if (fread(hdr, 1, PROM_HDR_V2_SIZE, in) != PROM_HDR_V2_SIZE)
		return -1;

	switch (hdr[0]) {
	case 1:
	case 2:
		*len = ((size_t)hdr[2] << 8) | hdr[3];
		break;
	case 3:
		if (fread(hdr + PROM_HDR_V2_SIZE, 1, rest, in) != rest)
			return -1;
		*len = ((size_t)hdr[4] << 24) | ((size_t)hdr[5] << 16) |
		       ((size_t)hdr[6] << 8) | hdr[7];
		break;
	default:
		return -1;
	}

	if (hdr[1] >= PROM_MAX_TYPE)
		return -1;

	return 0;
}

/*
 * The AVM WLAN blob describes itself: a little-endian u16 length at offset 0
 * and a little-endian u16 checksum at offset 2. XOR every u16 word of the blob
 * together with the checksum word taken as zero, and that result XOR the
 * stored word is 0xffff. Verified on every ath10k record we hold — both radios
 * of two FB7590 units and the FB7560's 5 GHz record. The FB7560's second
 * record is an ath9k EEPROM, which has neither field, so -c is wrong for it.
 */
static int blob_check(const unsigned char *b, size_t avail, size_t *blob_len)
{
	uint16_t acc = 0, stored;
	size_t len, i;

	if (avail < 4)
		return -1;

	len = b[0] | ((size_t)b[1] << 8);
	if (len < 4 || (len & 1) || len > avail)
		return -1;

	stored = b[2] | ((uint16_t)b[3] << 8);
	for (i = 0; i < len / 2; i++) {
		if (i == 1)
			continue;
		acc ^= b[2 * i] | ((uint16_t)b[2 * i + 1] << 8);
	}

	if ((uint16_t)(acc ^ stored) != 0xffff)
		return -1;

	*blob_len = len;
	return 0;
}

/*
 * The stream is positioned on a record's payload. Inflate it and work out
 * which bytes would be written. 'declared' is the length the record's header
 * claims, or 0 to not check it — the -e path does not, so that its behaviour
 * is unchanged.
 *
 * On EXTRACT_OK, *data points into buf and *len is what to write.
 */
static enum extract_result extract_payload(FILE *in, const struct extract_opts *o,
					   size_t declared, unsigned char *buf,
					   size_t bufsize, int *zret,
					   unsigned char **data, size_t *len,
					   size_t *inflated)
{
	size_t datasize = bufsize;
	size_t consumed = 0;
	size_t avail, blob_len;
	int ret;

	/*
	 * We have to see the whole stream to reverse it, to write it without a
	 * -l to bound it, to checksum it, or to hold it against the length its
	 * header declares.
	 */
	bool need_full = o->reversed || !o->limit || o->check || declared;

	ret = inflate_to_buffer(in, buf, &datasize, &consumed);
	if (need_full && ret != Z_STREAM_END) {
		*zret = ret;
		return EXTRACT_TRUNCATED;
	}

	ret = (ret == Z_STREAM_END) ? Z_OK : ret; /* normalize return value */
	if (ret != Z_OK) {
		*zret = ret;
		return EXTRACT_ZLIB;
	}

	*inflated = datasize;

	if (declared && consumed != declared)
		return EXTRACT_DECLARED_LEN;

	if (o->reversed)
		buffer_reverse(buf, datasize - 1);

	if (datasize <= o->skip)
		return EXTRACT_SHORT;

	avail = datasize - o->skip;

	if (o->check) {
		if (blob_check(buf + o->skip, avail, &blob_len))
			return EXTRACT_CHECKSUM;
		avail = blob_len;
	}

	*data = buf + o->skip;
	*len = o->limit ? MIN(o->limit, avail) : avail;

	return EXTRACT_OK;
}

/*
 * Find the record by type instead of by address.
 *
 * AVM's own reader never scans — avm_prom_load_config_packed()
 * (prom_config.c:717-744) walks a region it was handed, and the kernel gets
 * the per-unit offsets from the DT property "wlan_dect_configs" that the
 * urlader injects. Our DTB declares its own chosen node, so we never see that
 * table and used to guess the offsets from a hardcoded list. They differ
 * between units of the same hardware and bootloader revision, so the list was
 * a bet.
 *
 * This walks every byte of the input instead, and leans on the record being
 * self-describing to tell a real one from the header-shaped bytes that occur
 * by chance in bootloader code: the payload has to be a complete zlib stream
 * of exactly the declared length, and with -c the blob has to pass its own
 * checksum too. Measured over the four units we hold, 1 MiB of urlader each:
 * up to 155 byte pairs per type look like a header, and none of them survives
 * the zlib test — leaving only the real records and their mirrors.
 *
 * Lowest offset wins, and a candidate that fails validation is simply skipped,
 * which is also how a bad mirror is passed over.
 */
static enum extract_result extract_by_type(FILE *in, int type,
					   const struct extract_opts *o,
					   unsigned char *buf, size_t bufsize,
					   int *zret, unsigned char **data,
					   size_t *len)
{
	unsigned char win[SCAN_CHUNK + 1];
	size_t carry = 0, got, i, inflated;
	long base = 0;

	if (fseek(in, 0, SEEK_SET)) {
		perror("Failed to rewind input");
		return EXTRACT_ZLIB;
	}

	while ((got = fread(win + carry, 1, SCAN_CHUNK, in)) > 0) {
		size_t avail = carry + got;
		long resume = base + (long)avail;

		for (i = 0; i + 1 < avail; i++) {
			size_t declared;
			long off = base + (long)i;

			if (win[i] < 1 || win[i] > 3)
				continue;
			if (win[i + 1] != (unsigned char)type)
				continue;

			if (fseek(in, off, SEEK_SET)) {
				perror("Failed to seek to candidate record");
				return EXTRACT_ZLIB;
			}

			if (!prom_read_hdr(in, &declared) && declared &&
			    extract_payload(in, o, declared, buf, bufsize, zret,
					    data, len, &inflated) == EXTRACT_OK)
				return EXTRACT_OK;

			if (fseek(in, resume, SEEK_SET)) {
				perror("Failed to resume the scan");
				return EXTRACT_ZLIB;
			}
		}

		if (ferror(in))
			break;

		base += (long)(avail - 1);
		win[0] = win[avail - 1];
		carry = 1;
	}

	if (ferror(in)) {
		perror("Failure while scanning for the record");
		return EXTRACT_ZLIB;
	}

	fprintf(stderr, "No valid prom_config record of type %d in the input\n",
		type);
	return EXTRACT_NOT_FOUND;
}

/*
 * Walk the record chain from the current position, matching the first two
 * header bytes as one big-endian 16-bit value. AVM pads between records with
 * 0xff, so this only reaches a record whose own header -s points at.
 */
static int extract_by_entry(FILE *in, int entry)
{
	struct cal_entry cal = { .len = 0 };
	int ret;

	do {
		ret = fseek(in, be16toh(cal.len), SEEK_CUR);
		if (feof(in)) {
			fprintf(stderr, "Reached end of file, but didn't find the matching entry\n");
			return -1;
		} else if (ferror(in)) {
			perror("Failure during seek");
			return -1;
		}

		ret = fread(&cal, 1, sizeof cal, in);
		if (ret != sizeof cal)
			return -1;
	} while (entry != cal.id || cal.id == 0xffff);

	if (cal.id == 0xffff) {
		fprintf(stderr, "Reached end of filesystem, but didn't find the matching entry\n");
		return -1;
	}

	return 0;
}

/* compress or decompress from stdin to stdout */
int main(int argc, char **argv)
{
	struct extract_opts o = { .limit = 0, .skip = 0, .reversed = false, .check = false };
	unsigned char *buf = NULL, *data = NULL;
	FILE *in = stdin;
	FILE *out = stdout;
	size_t bufsize = DEFAULT_BUFFERSIZE;
	size_t len = 0, inflated = 0;
	int initial_offset = 0;
	int entry = -1;
	int type = -1;
	int zret = Z_OK;
	enum extract_result res;
	int ret;
	int opt;

	while ((opt = getopt(argc, argv, "s:e:o:l:i:t:rc")) != -1) {
		switch (opt) {
		case 's':
			initial_offset = (int)get_num(optarg);
			if (errno) {
				perror("Failed to parse seek offset");
				goto out_bad;
			}
			break;
		case 'e':
			entry = (int) htobe16(get_num(optarg));
			if (errno) {
				perror("Failed to entry id");
				goto out_bad;
			}
			break;
		case 't': {
			unsigned int t = get_num(optarg);

			if (errno) {
				perror("Failed to parse prom_config type");
				goto out_bad;
			}
			if (t >= PROM_MAX_TYPE) {
				fprintf(stderr, "prom_config type %u is out of range\n",
					t);
				goto out_bad;
			}
			type = (int)t;
			break;
		}
		case 'o':
			out = fopen(optarg, "w");
			if (!out) {
				perror("Failed to create output file");
				goto out_bad;
			}
			break;
		case 'l':
			o.limit = (size_t)get_num(optarg);
			if (errno) {
				perror("Failed to parse limit");
				goto out_bad;
			}
			break;
		case 'i':
			o.skip = (size_t)get_num(optarg);
			if (errno) {
				perror("Failed to parse skip");
				goto out_bad;
			}
			break;
		case 'r':
			o.reversed = true;
			break;
		case 'c':
			o.check = true;
			break;
		default: /* '?' */
			usage();
		}
	}

	if ((entry == -1) == (type == -1))
		usage();

	/* -t finds the record itself, so an offset into the input is meaningless */
	if (type != -1 && initial_offset)
		usage();

	if (argc > 1 && optind <= argc) {
		in = fopen(argv[optind], "r");
		if (!in) {
			perror("Failed to open input file");
			goto out_bad;
		}
	}

	/*
	 * Only keep the default buffer size if we need complete data for
	 * reversal and didn't ask for a bigger limit.
	 */
	if (o.limit && !(o.reversed && bufsize >= o.limit + o.skip))
		bufsize = o.limit + o.skip;

	/*
	 * A scan validates a candidate against the whole of its stream, so -l
	 * must not be allowed to cut the buffer below what a record inflates
	 * to. 129 KiB is therefore also the largest record -t can extract.
	 */
	if (type != -1 && bufsize < DEFAULT_BUFFERSIZE)
		bufsize = DEFAULT_BUFFERSIZE;

	buf = malloc(bufsize);
	assert(buf != NULL);

	if (type != -1) {
		res = extract_by_type(in, type, &o, buf, bufsize, &zret, &data, &len);
		if (res != EXTRACT_OK)
			goto out_bad;
	} else {
		if (initial_offset) {
			ret = fseek(in, initial_offset, SEEK_CUR);
			if (ret) {
				perror("Failed to seek to calibration table");
				goto out_bad;
			}
		}

		if (extract_by_entry(in, entry))
			goto out_bad;

		/* the -e path has never checked the declared length; keep it that way */
		res = extract_payload(in, &o, 0, buf, bufsize, &zret, &data, &len,
				      &inflated);
		switch (res) {
		case EXTRACT_OK:
			break;
		case EXTRACT_TRUNCATED:
			fprintf(stderr, "Failed: Data exceeds buffer size of %u. Refusing to reverse"
					" or store incomplete data."
					" Use a higher limit [-l] to increase buffer size.\n",
					(unsigned int) bufsize);
			goto out_bad;
		case EXTRACT_ZLIB:
			zerr(zret);
			goto out_bad;
		case EXTRACT_SHORT:
			fprintf(stderr, "Failed to skip %u bytes, total data size is %u!\n",
					(unsigned int)o.skip, (unsigned int)inflated);
			goto out_bad;
		case EXTRACT_CHECKSUM:
			fprintf(stderr, "Failed: the blob did not pass its own checksum\n");
			goto out_bad;
		default:
			goto out_bad;
		}
	}

	if (fwrite(data, len, 1, out) != 1 || ferror(out)) {
		fprintf(stderr, "Failed to write data buffer to output file");
		goto out_bad;
	}

	ret = EXIT_SUCCESS;
	goto out;

out_bad:
	ret = EXIT_FAILURE;

out:
	if (in)
		fclose(in);
	if (out)
		fclose(out);
	free(buf);
	return ret;
}
