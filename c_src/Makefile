ERL ?= erl
BASEDIR=$(CURDIR)
PRIVDIR=./priv

NIF_DIR=c_src
NIF_ENV=c_src/env.mk

NIF_SOURCES=$(NIF_DIR)/localize_address_nif.c
NIF_OBJS=$(NIF_DIR)/localize_address_nif.o
NIF_SO=$(PRIVDIR)/localize_address_nif.so

UNAME_SYS := $(shell uname -s)
UNAME_ARCH := $(shell uname -p)

ifeq ($(UNAME_SYS), Darwin)
	ifeq ($(UNAME_ARCH), arm)
		CC ?= cc
		CFLAGS = -O3 -std=c11 -arch arm64 -Wall
		LDFLAGS = -arch arm64 -flat_namespace -undefined dynamic_lookup
	else
		CC ?= cc
		CFLAGS = -O3 -std=c11 -arch x86_64 -Wall
		LDFLAGS = -arch x86_64 -flat_namespace -undefined dynamic_lookup
	endif
else ifeq ($(UNAME_SYS), FreeBSD)
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 -finline-functions -Wall
else ifeq ($(UNAME_SYS), Linux)
	CC ?= gcc
	CFLAGS ?= -O3 -std=c11 -finline-functions -Wall
endif

CFLAGS += -fPIC -I$(ERTS_INCLUDE_DIR) -I$(ERL_INTERFACE_INCLUDE_DIR)

# On OTP 23 and later, liberl_interface.a doesn't exist and
# isn't required
ifneq ("$(wildcard $(ERL_INTERFACE_LIB_DIR)/liberl_interface.a)","")
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lerl_interface -lei
else
    LDLIBS += -L$(ERL_INTERFACE_LIB_DIR) -lei
endif

LDFLAGS += -shared

# ── libpostal detection ────────────────────────────────────────
# Try pkg-config first, then Homebrew paths, then system paths.

LIBPOSTAL_CFLAGS = $(shell pkg-config --cflags libpostal 2>/dev/null)
LIBPOSTAL_LIBS = $(shell pkg-config --libs libpostal 2>/dev/null)

ifeq ($(LIBPOSTAL_LIBS),)
  ifeq ($(UNAME_SYS), Darwin)
    HOMEBREW_LP := $(shell [ -d /opt/homebrew/opt/libpostal ] && echo /opt/homebrew/opt/libpostal || \
                           ([ -d /usr/local/opt/libpostal ] && echo /usr/local/opt/libpostal || echo ""))
    ifneq ($(HOMEBREW_LP),)
      LIBPOSTAL_CFLAGS = -I$(HOMEBREW_LP)/include
      LIBPOSTAL_LIBS = -L$(HOMEBREW_LP)/lib -lpostal
    endif
  endif
endif

# Last resort: assume system paths
ifeq ($(LIBPOSTAL_LIBS),)
  LIBPOSTAL_CFLAGS =
  LIBPOSTAL_LIBS = -lpostal
endif

# ── Aggregate flags ─────────────────────────────────────────────
ALL_CFLAGS = $(LIBPOSTAL_CFLAGS)
ALL_LIBS = $(LIBPOSTAL_LIBS)

all: $(NIF_ENV) $(NIF_SO)

clean:
	@rm -rf $(NIF_SO) $(NIF_OBJS)

distclean: clean
	@rm -rf $(NIF_ENV)

$(NIF_SO): $(NIF_OBJS)
	@mkdir -p $(PRIVDIR)
	$(CC) $(NIF_OBJS) $(LDFLAGS) $(LDLIBS) $(ALL_LIBS) -o $(NIF_SO)

%.o: %.c
	$(CC) -c $(CFLAGS) $(ALL_CFLAGS) $< -o $@

$(NIF_ENV):
	@$(ERL) -eval "file:write_file(\"$(NIF_ENV)\", \
		io_lib:format( \
		\"ERTS_INCLUDE_DIR ?= ~s/erts-~s/include/~n\" \
		\"ERL_INTERFACE_INCLUDE_DIR ?= ~s~n\" \
		\"ERL_INTERFACE_LIB_DIR ?= ~s~n\", \
		[code:root_dir(), erlang:system_info(version), \
		code:lib_dir(erl_interface, include), \
		code:lib_dir(erl_interface, lib)])), \
		halt()."

-include $(NIF_ENV)
