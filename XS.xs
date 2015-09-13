#define PERL_NO_GET_CONTEXT 1
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define CAN_IS()           (s < send)
#define CAN_NEXT()         ((s + ulen) < send)
#define IS_CHAR(c)         (ch == (c))
#define IS_RANGE(a, b)     ((ch >= (a)) && (ch <= (b)))

#define FUNC_DECL(funcname, test)                                          \
  STRLEN funcname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) { \
  STRLEN len;                                                              \
  STRLEN ulen;                                                             \
  U8 *s = (s_force != NULL) ? s_force : (U8 *)SvPV(sv, len);               \
  U8 *send = (send_force != NULL) ? send_force : (s + len);                \
  STRLEN retval = 0;                                                       \
                                                                           \
  if (! SvUTF8(sv)) { /* one byte == one char, so no endianness */         \
    ulen = 1;                                                              \
    if (pos) {                                                             \
      s += pos;                                                            \
    }                                                                      \
    while (CAN_IS()) {                                                     \
      U8 ch = *s;                                                          \
      if (test) {                                                          \
        retval++;                                                          \
        s++;                                                               \
      } else {                                                             \
        break;                                                             \
      }                                                                    \
    }                                                                      \
  } else {                                                                 \
    if (pos) {                                                             \
      s = utf8_hop(s, pos);                                                \
    }                                                                      \
    while (CAN_IS()) {                                                     \
      UV ch = NATIVE_TO_UNI(utf8_to_uvchr_buf(s, send, &ulen));            \
      if (test) {                                                          \
        retval++;                                                          \
        s += ulen;                                                         \
      } else {                                                             \
        break;                                                             \
      }                                                                    \
    }                                                                      \
  }                                                                        \
  return retval;                                                           \
}

/*
  Note that we always assume caller is giving a start
  position that is OK. All the offset manipulation is to
  avoid to recalculate offset at every bunch of calls
*/

FUNC_DECL(is_XML10_S, IS_CHAR(0x20) || IS_CHAR(0x9) || IS_CHAR(0xD) || IS_CHAR(0xA))

MODULE = MarpaX::Languages::XML		PACKAGE = MarpaX::Languages::XML::XS
PROTOTYPES: DISABLE

STRLEN
is_XML10_S(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_S(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL
