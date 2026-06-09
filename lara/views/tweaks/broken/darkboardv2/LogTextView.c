//Dummy implementation
// No logic
// created by notthemystery

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <pthread.h>
#include <time.h>
#include "LogTextView.h

static BOOL g_verbose = NO;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static char *g_buffer = NULL;
static size_t g_buffer_size = 0;

static void append_buffer(const char *msg)
{
    if (!msg) return;

    pthread_mutex_lock(&g_lock);

    size_t len = strlen(msg);

    char *newbuf = realloc(g_buffer, g_buffer_size + len + 2);
    if (!newbuf) {
        pthread_mutex_unlock(&g_lock);
        return;
    }

    g_buffer = newbuf;

    memcpy(g_buffer + g_buffer_size, msg, len);
    g_buffer_size += len;

    g_buffer[g_buffer_size++] = '\n';
    g_buffer[g_buffer_size] = '\0';

    pthread_mutex_unlock(&g_lock);
}

void log_init(void)
{
    // no-op init
    g_verbose = NO;
}

void log_write(const char *msg)
{
    if (!msg) return;
    append_buffer(msg);
}

void log_write_raw_no_timestamp(const char *msg)
{
    if (!msg) return;
    append_buffer(msg);
}

void log_set_verbose(BOOL enabled)
{
    g_verbose = enabled;
}

BOOL log_verbose_enabled(void)
{
    return g_verbose;
}

// printf-style user log
void log_user(const char *fmt, ...)
{
    if (!fmt) return;

    char buf[2048];

    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    append_buffer(buf);
}

void log_session_begin(void)
{
    append_buffer("[session begin]");
}

void log_session_end(void)
{
    append_buffer("[session end]");
}

NSString * _Nullable log_most_recent_session_path(void)
{
    return nil; // dummy
}

NSString *log_inapp_buffer_snapshot(void)
{
    if (!g_buffer) {
        return @""; // empty snapshot
    }
    return [NSString stringWithUTF8String:g_buffer];
}
