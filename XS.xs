#define PERL_NO_GET_CONTEXT 1
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define NO_USERCODE
#define IS_CHAR(c)         (ch == (c))
#define IS_RANGE(a, b)     ((ch >= (a)) && (ch <= (b)))

#define FUNC_ALIAS(funcname, alias)                                        \
static                                                                     \
STRLEN funcname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) {   \
 return alias(aTHX_ sv, pos, s_force, send_force);                         \
}                                                                          \

/*
  Note that we always assume caller is giving a start
  position that is OK. All the offset manipulation is to
  avoid to recalculate offset at every recursive call
*/

#define FUNC_DECL(funcname, testASCII, testUTF8, retval, usercode)         \
static                                                                     \
STRLEN funcname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) {   \
  STRLEN len;                                                              \
  STRLEN ulen = 1;                                                         \
  U8 *s = (s_force != NULL) ? s_force : (U8 *)SvPV(sv, len);               \
  U8 *send = (send_force != NULL) ? send_force : (s + len);                \
  STRLEN retval = 0;                                                       \
                                                                           \
  if (! SvUTF8(sv)) { /* one byte == one char, so no endianness */         \
    ulen = 1;                                                              \
    if (pos) {                                                             \
      s += pos;                                                            \
    }                                                                      \
    while (s < send) {                                                     \
      U8 ch = *s;                                                          \
      if (testASCII) {                                                     \
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
    while (s < send) {                                                     \
      UV ch = NATIVE_TO_UNI(utf8_to_uvchr_buf(s, send, &ulen));            \
      if (testUTF8) {                                                      \
        retval++;                                                          \
        s += ulen;                                                         \
      } else {                                                             \
        break;                                                             \
      }                                                                    \
    }                                                                      \
  }                                                                        \
  usercode                                                                 \
  return retval;                                                           \
}

/* ======================================================================= */
/*              Definitions common to XML 1.0 and XML 1.1                  */
/* ======================================================================= */

/* _NAME = qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+} */
#define XML_NAME_TRAILER_ASCII()                \
  IS_CHAR(':')               ||                 \
  IS_RANGE('A', 'Z')         ||                 \
  IS_CHAR('_')               ||                 \
  IS_RANGE('a', 'z')         ||                 \
  IS_RANGE(0xC0, 0xD6)       ||                 \
  IS_RANGE(0xD8, 0xF6)       ||                 \
  IS_CHAR('-')               ||                 \
  IS_CHAR('.')               ||                 \
  IS_RANGE('0', '9')         ||                 \
  IS_CHAR(0xB7)              ||                 \
  IS_RANGE(0xF8, 0xFF)

#define XML_NAME_TRAILER_UTF8()                 \
  XML_NAME_TRAILER_ASCII()   ||                 \
  IS_RANGE(0x100, 0x2FF)     ||                 \
  IS_RANGE(0x370, 0x37D)     ||                 \
  IS_RANGE(0x37F, 0x1FFF)    ||                 \
  IS_RANGE(0x200C, 0x200D)   ||                 \
  IS_RANGE(0x2070, 0x218F)   ||                 \
  IS_RANGE(0x2C00, 0x2FEF)   ||                 \
  IS_RANGE(0x3001, 0xD7FF)   ||                 \
  IS_RANGE(0xF900, 0xFDCF)   ||                 \
  IS_RANGE(0xFDF0, 0xFFFD)   ||                 \
  IS_RANGE(0x10000, 0xEFFFF) ||                 \
  IS_RANGE(0x300, 0x036F)    ||                 \
  IS_RANGE(0x203F, 0x2040)

FUNC_DECL(is_XML_NAME_TRAILER, XML_NAME_TRAILER_ASCII(), XML_NAME_TRAILER_UTF8(), rc, NO_USERCODE)

#define XML_NAME_HEADER_ASCII()                 \
  IS_CHAR(':')               ||                 \
  IS_RANGE('A', 'Z')         ||                 \
  IS_CHAR('_')               ||                 \
  IS_RANGE('a', 'z')         ||                 \
  IS_RANGE(0xC0, 0xD6)       ||                 \
  IS_RANGE(0xD8, 0xF6)       ||                 \
  IS_RANGE(0xF8, 0xFF)

#define XML_NAME_HEADER_UTF8()                 \
  XML_NAME_HEADER_ASCII()    ||                \
  IS_RANGE(0x100, 0x2FF)     ||                \
  IS_RANGE(0x370, 0x37D)     ||                \
  IS_RANGE(0x37F, 0x1FFF)    ||                \
  IS_RANGE(0x200C, 0x200D)   ||                \
  IS_RANGE(0x2070, 0x218F)   ||                \
  IS_RANGE(0x2C00, 0x2FEF)   ||                \
  IS_RANGE(0x3001, 0xD7FF)   ||                \
  IS_RANGE(0xF900, 0xFDCF)   ||                \
  IS_RANGE(0xFDF0, 0xFFFD)   ||                \
  IS_RANGE(0x10000, 0xEFFFF)

FUNC_DECL(is_XML_NAME, XML_NAME_HEADER_ASCII(), XML_NAME_HEADER_UTF8(), 
          rc,
          if (rc) { rc += is_XML_NAME_TRAILER(aTHX_ sv, 0, s, send); }
          )

/* _NMTOKENMANY = qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]++}p, */

#define XML_S_ASCII() IS_CHAR(0x20) || IS_CHAR(0x9) || IS_CHAR(0xD) || IS_CHAR(0xA)
#define XML_S_UTF8() XML_S_ASCII()
FUNC_DECL(is_XML_S, XML_S_ASCII(), XML_S_UTF8(), rc, NO_USERCODE)

/* ======================================================================= */
/*                                 XML 1.0                                 */
/* ======================================================================= */
FUNC_ALIAS(is_XML10_NAME, is_XML_NAME)
FUNC_ALIAS(is_XML10_S,    is_XML_S)

/* ======================================================================= */
/*                                 XML 1.1                                 */
/* ======================================================================= */
FUNC_ALIAS(is_XML11_NAME, is_XML_NAME)
FUNC_ALIAS(is_XML11_S,    is_XML_S)

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

STRLEN
is_XML11_S(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_S(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL
