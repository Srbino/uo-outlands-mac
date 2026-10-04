#ifndef OUTLANDS_ARCHIVE_SHIM_H
#define OUTLANDS_ARCHIVE_SHIM_H
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
// Minimal declarations for macOS's system libarchive. No third-party binary is bundled.
// Signatures follow libarchive's archive.h and archive_entry.h (v3.7.7).
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_filter_gzip(struct archive *);
int archive_read_support_format_tar(struct archive *);
int archive_read_open_fd(struct archive *, int, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_free(struct archive *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
const char *archive_entry_hardlink_utf8(struct archive_entry *);
const char *archive_entry_symlink_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
#endif
