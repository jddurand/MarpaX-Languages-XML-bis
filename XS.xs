#define PERL_NO_GET_CONTEXT 1
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define XML_ARRAY_LENGTH(p) (sizeof((p))/sizeof((p)[0]))
#define XML_NO_USERCODE()
#define XML_IS_CHAR(c)         (ch == (c))
#define XML_IS_NOT_CHAR(c)     (ch != (c))
#define XML_IS_RANGE(a, b)     ((ch >= (a)) && (ch <= (b)))

#ifndef NDEBUG
#include <ctype.h>
#define XML_PRINT_CHAR_STATUS(funcname, ch, status)                     \
  do {                                                                  \
  unsigned char c = (unsigned char) ch;                                 \
  int i = (int) c;                                                      \
  if (isgraph(i)) {                                                     \
    fprintf(stderr, "%s: '%c' %s\n", #funcname, c, status);             \
  } else {                                                              \
    fprintf(stderr, "%s: 0x%lx %s\n", #funcname, (unsigned long) ch, status); \
  }                                                                     \
  } while (0)
#define XML_PRINT_FUNC_STATUS(funcname, retval)                         \
  do {                                                                  \
    fprintf(stderr, "%s returns %ld\n", #funcname, (unsigned long) retval); \
  } while (0)
#else
#define XML_PRINT_FUNC_STATUS(funcname, ch, status)
#define XML_PRINT_FUNC_STATUS(funcname, retval)
#endif

#define XML_FUNC_ALIAS(funcname, alias)                                    \
static                                                                     \
STRLEN funcname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) {   \
 return alias(aTHX_ sv, pos, s_force, send_force);                         \
}                                                                          \

/*
  Note that we always assume caller is giving a start
  position that is OK. All the offset manipulation is to
  avoid to recalculate offset at every recursive call
*/

#define XML_FUNC_DECL(funcname, testASCII, testUTF8, retval, usercode)     \
static                                                                     \
STRLEN funcname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) {   \
  STRLEN  len;                                                             \
  STRLEN  ulen;                                                            \
  U8     *s      = (s_force != NULL) ? s_force : (U8 *)SvPV(sv, len);      \
  U8     *send   = (send_force != NULL) ? send_force : (s + len);          \
  STRLEN  retval = 0;                                                      \
                                                                           \
  if (! SvUTF8(sv)) {                                                      \
    ulen = 1;                                                              \
    if (pos) {                                                             \
      s += pos;                                                            \
    }                                                                      \
    while (s < send) {                                                     \
      U8 ch = *s;                                                          \
      if (testASCII) {                                                     \
        XML_PRINT_CHAR_STATUS(funcname, ch, "ok (ASCII mode)");            \
        retval++;                                                          \
        s++;                                                               \
      } else {                                                             \
        XML_PRINT_CHAR_STATUS(funcname, ch, "ko (ASCII mode)");            \
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
        XML_PRINT_CHAR_STATUS(funcname, ch, "ok (UTF8 mode)");             \
        retval++;                                                          \
        s += ulen;                                                         \
      } else {                                                             \
        XML_PRINT_CHAR_STATUS(funcname, ch, "ko (UTF8 mode)");             \
        break;                                                             \
      }                                                                    \
    }                                                                      \
  }                                                                        \
  usercode                                                                 \
  XML_PRINT_FUNC_STATUS(funcname, retval);                                 \
  return retval;                                                           \
}

/* ======================================================================= */
/*              Static definitions used for lookaheads                     */
/* ======================================================================= */
UV CHARDATAMANY_LOOKAHEAD[]    = { /* ']', */ ']', '>' };
UV COMMENTCHARMANY_LOOKAHEAD[] = { /* '-', */ '-'      };
UV PITARGET_LOOKAHEAD1[]       = { /* 'x', */ 'm', 'l' }; /* C.f. code works also with 'X' */
UV PITARGET_LOOKAHEAD2[]       = { /* 'x', */ 'm', 'L' }; /* C.f. code works also with 'X' */
UV PITARGET_LOOKAHEAD3[]       = { /* 'x', */ 'M', 'l' }; /* C.f. code works also with 'X' */
UV PITARGET_LOOKAHEAD4[]       = { /* 'x', */ 'M', 'L' }; /* C.f. code works also with 'X' */
UV CDATAMANY_LOOKAHEAD[]       = { /* ']', */ ']', '>' };
UV PICHARDATAMANY_LOOKAHEAD[]  = { /* '?', */ '>'      };
UV IGNOREMANY_LOOKAHEAD1[]     = { /* '<', */ '!', '[' };
UV IGNOREMANY_LOOKAHEAD2[]     = { /* ']', */ ']', '>' };

/* ======================================================================= */
/*          Internal functions used to search for a string                 */
/* ======================================================================= */
static
STRLEN _is_XML_STRING(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force, STRLEN nuv, UV string[], bool partial) {
  STRLEN  len;
  STRLEN  ulen;
  U8     *s      = (s_force != NULL) ? s_force : (U8 *)SvPV(sv, len);
  U8     *send   = (send_force != NULL) ? send_force : (s + len);
  STRLEN  retval = 0;
  STRLEN  i      = 0;

  if (! SvUTF8(sv)) {
    ulen = 1;
    if (pos) {
      s += pos;
    }
    while ((i < nuv) && (s < send)) {
      U8 ch = *s;
      if (string[i] == (UV)ch) {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING, ch, "ok (ASCII mode)");
        retval++;
        s++;
        i++;
      } else {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING, ch, "ko (ASCII mode)");
        break;
      }
    }
  } else {
    if (pos) {
      s = utf8_hop(s, pos);
    }
    while ((i < nuv) && (s < send)) {
      UV ch = NATIVE_TO_UNI(utf8_to_uvchr_buf(s, send, &ulen));
      if (string[i] == ch) {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING, ch, "ok (UTF8 mode)");
        retval++;
        s += ulen;
        i++;
      } else {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING, ch, "ko (UTF8 mode)");
        break;
      }
    }
  }

  if (retval != i) {
    /* sv does not start with string */
    retval = 0;
  } else if ((! partial) && (s < send)) {
    /* sv start with string but this is a partial match */
    retval = 0;
  }

  XML_PRINT_FUNC_STATUS(_is_XML_STRING, retval);                                 \
  return retval;
}

/* ======================================================================= */
/*              Definitions common to XML 1.0 and XML 1.1                  */
/* ======================================================================= */

/* _NAME = qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+} */
#define XML_NAME_TRAILER_ASCII() (                                      \
                                  XML_IS_CHAR(':')               ||     \
                                  XML_IS_RANGE('A', 'Z')         ||     \
                                  XML_IS_CHAR('_')               ||     \
                                  XML_IS_RANGE('a', 'z')         ||     \
                                  XML_IS_RANGE(0xC0, 0xD6)       ||     \
                                  XML_IS_RANGE(0xD8, 0xF6)       ||     \
                                  XML_IS_CHAR('-')               ||     \
                                  XML_IS_CHAR('.')               ||     \
                                  XML_IS_RANGE('0', '9')         ||     \
                                  XML_IS_CHAR(0xB7)              ||     \
                                  XML_IS_RANGE(0xF8, 0xFF)              \
                                                                        )

#define XML_NAME_TRAILER_UTF8() (                                       \
                                 XML_NAME_TRAILER_ASCII()       ||      \
                                 XML_IS_RANGE(0x100, 0x2FF)     ||      \
                                 XML_IS_RANGE(0x370, 0x37D)     ||      \
                                 XML_IS_RANGE(0x37F, 0x1FFF)    ||      \
                                 XML_IS_RANGE(0x200C, 0x200D)   ||      \
                                 XML_IS_RANGE(0x2070, 0x218F)   ||      \
                                 XML_IS_RANGE(0x2C00, 0x2FEF)   ||      \
                                 XML_IS_RANGE(0x3001, 0xD7FF)   ||      \
                                 XML_IS_RANGE(0xF900, 0xFDCF)   ||      \
                                 XML_IS_RANGE(0xFDF0, 0xFFFD)   ||      \
                                 XML_IS_RANGE(0x10000, 0xEFFFF) ||      \
                                 XML_IS_RANGE(0x300, 0x036F)    ||      \
                                 XML_IS_RANGE(0x203F, 0x2040)           \
                                )

XML_FUNC_DECL(
              is_XML_NAME_TRAILER,
              XML_NAME_TRAILER_ASCII(),
              XML_NAME_TRAILER_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

#define XML_NAME_HEADER_ASCII() (                                       \
                                 XML_IS_CHAR(':')               ||      \
                                 XML_IS_RANGE('A', 'Z')         ||      \
                                 XML_IS_CHAR('_')               ||      \
                                 XML_IS_RANGE('a', 'z')         ||      \
                                 XML_IS_RANGE(0xC0, 0xD6)       ||      \
                                 XML_IS_RANGE(0xD8, 0xF6)       ||      \
                                 XML_IS_RANGE(0xF8, 0xFF)               \
                                )

#define XML_NAME_HEADER_UTF8() (                                        \
                                XML_NAME_HEADER_ASCII()        ||       \
                                XML_IS_RANGE(0x100, 0x2FF)     ||       \
                                XML_IS_RANGE(0x370, 0x37D)     ||       \
                                XML_IS_RANGE(0x37F, 0x1FFF)    ||       \
                                XML_IS_RANGE(0x200C, 0x200D)   ||       \
                                XML_IS_RANGE(0x2070, 0x218F)   ||       \
                                XML_IS_RANGE(0x2C00, 0x2FEF)   ||       \
                                XML_IS_RANGE(0x3001, 0xD7FF)   ||       \
                                XML_IS_RANGE(0xF900, 0xFDCF)   ||       \
                                XML_IS_RANGE(0xFDF0, 0xFFFD)   ||       \
                                XML_IS_RANGE(0x10000, 0xEFFFF)          \
                               )

XML_FUNC_DECL(
              is_XML_NAME,
              XML_NAME_HEADER_ASCII(),
              XML_NAME_HEADER_UTF8(), 
              rc,
              if (rc) {
                rc += is_XML_NAME_TRAILER(aTHX_ sv, 0, s, send);
              }
              )

/* The following remains internal and is used when there is NameSpace support, which is doing special treatment of the ':' character */
/* _NAME_WITHOUT_COLON = qr{\G[A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+} */
#define XML_NAME_WITHOUT_COLON_TRAILER_ASCII() (                                  \
                                                XML_IS_RANGE('A', 'Z')         || \
                                                XML_IS_CHAR('_')               || \
                                                XML_IS_RANGE('a', 'z')         || \
                                                XML_IS_RANGE(0xC0, 0xD6)       || \
                                                XML_IS_RANGE(0xD8, 0xF6)       || \
                                                XML_IS_CHAR('-')               || \
                                                XML_IS_CHAR('.')               || \
                                                XML_IS_RANGE('0', '9')         || \
                                                XML_IS_CHAR(0xB7)              || \
                                                XML_IS_RANGE(0xF8, 0xFF)          \
                                               )

#define XML_NAME_WITHOUT_COLON_TRAILER_UTF8() (                                          \
                                               XML_NAME_WITHOUT_COLON_TRAILER_ASCII() || \
                                               XML_IS_RANGE(0x100, 0x2FF)             || \
                                               XML_IS_RANGE(0x370, 0x37D)             || \
                                               XML_IS_RANGE(0x37F, 0x1FFF)            || \
                                               XML_IS_RANGE(0x200C, 0x200D)           || \
                                               XML_IS_RANGE(0x2070, 0x218F)           || \
                                               XML_IS_RANGE(0x2C00, 0x2FEF)           || \
                                               XML_IS_RANGE(0x3001, 0xD7FF)           || \
                                               XML_IS_RANGE(0xF900, 0xFDCF)           || \
                                               XML_IS_RANGE(0xFDF0, 0xFFFD)           || \
                                               XML_IS_RANGE(0x10000, 0xEFFFF)         || \
                                               XML_IS_RANGE(0x300, 0x036F)            || \
                                               XML_IS_RANGE(0x203F, 0x2040)              \
                                              )

XML_FUNC_DECL(
              is_XML_NAME_WITHOUT_COLON_TRAILER,
              XML_NAME_WITHOUT_COLON_TRAILER_ASCII(),
              XML_NAME_WITHOUT_COLON_TRAILER_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

XML_FUNC_DECL(
              is_XML_NAME_WITHOUT_COLON_TRAILER_THEN_NOCOLON,
              XML_NAME_WITHOUT_COLON_TRAILER_ASCII(),
              XML_NAME_WITHOUT_COLON_TRAILER_UTF8(),
              rc,
              if (rc) {
                UV colon[] = { ':' };
                if (_is_XML_STRING(aTHX_ sv, 0, s, send, 1, colon, true)) {
                  rc = 0;
                }
              }
              )

#define XML_NAME_WITHOUT_COLON_HEADER_ASCII() (                                  \
                                               XML_IS_RANGE('A', 'Z')         || \
                                               XML_IS_CHAR('_')               || \
                                               XML_IS_RANGE('a', 'z')         || \
                                               XML_IS_RANGE(0xC0, 0xD6)       || \
                                               XML_IS_RANGE(0xD8, 0xF6)       || \
                                               XML_IS_RANGE(0xF8, 0xFF)          \
                                              )

#define XML_NAME_WITHOUT_COLON_HEADER_UTF8() (                                         \
                                              XML_NAME_WITHOUT_COLON_HEADER_ASCII() || \
                                              XML_IS_RANGE(0x100, 0x2FF)            || \
                                              XML_IS_RANGE(0x370, 0x37D)            || \
                                              XML_IS_RANGE(0x37F, 0x1FFF)           || \
                                              XML_IS_RANGE(0x200C, 0x200D)          || \
                                              XML_IS_RANGE(0x2070, 0x218F)          || \
                                              XML_IS_RANGE(0x2C00, 0x2FEF)          || \
                                              XML_IS_RANGE(0x3001, 0xD7FF)          || \
                                              XML_IS_RANGE(0xF900, 0xFDCF)          || \
                                              XML_IS_RANGE(0xFDF0, 0xFFFD)          || \
                                              XML_IS_RANGE(0x10000, 0xEFFFF)           \
                                             )

XML_FUNC_DECL(
              is_XML_NAME_WITHOUT_COLON,
              XML_NAME_WITHOUT_COLON_HEADER_ASCII(),
              XML_NAME_WITHOUT_COLON_HEADER_UTF8(), 
              rc,
              if (rc) {
                rc += is_XML_NAME_WITHOUT_COLON_TRAILER(aTHX_ sv, 0, s, send);
              }
              )

XML_FUNC_DECL(
              is_XML_NAME_WITHOUT_COLON_THEN_NOCOLON,
              XML_NAME_WITHOUT_COLON_HEADER_ASCII(),
              XML_NAME_WITHOUT_COLON_HEADER_UTF8(), 
              rc,
              if (rc) {
                STRLEN rc2 = is_XML_NAME_WITHOUT_COLON_TRAILER_THEN_NOCOLON(aTHX_ sv, 0, s, send);
                if (rc2) {
                  rc += rc2;
                } else {
                  rc = 0;
                }
              }
              )

XML_FUNC_DECL(
              is_XML_COLON_THEN_NAME_WITHOUT_COLON_THEN_NOCOLON,
              (! rc) && XML_IS_CHAR(':'),
              (! rc) && XML_IS_CHAR(':'),
              rc,
              if (rc) {
                STRLEN rc2 = is_XML_NAME_WITHOUT_COLON_THEN_NOCOLON(aTHX_ sv, 0, s, send);
                if (rc2) {
                  rc += rc2;
                } else {
                  rc = 0;
                }
              }
              )


/* _NMTOKENMANY = qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]++} */
#define XML_NMTOKENMANY_ASCII() (                                       \
                                 XML_IS_CHAR(':')               ||      \
                                 XML_IS_RANGE('A', 'Z')         ||      \
                                 XML_IS_CHAR('_')               ||      \
                                 XML_IS_RANGE('a', 'z')         ||      \
                                 XML_IS_RANGE(0xC0, 0xD6)       ||      \
                                 XML_IS_RANGE(0xD8, 0xF6)       ||      \
                                 XML_IS_RANGE(0xF8, 0xFF)       ||      \
                                 XML_IS_CHAR('-')               ||      \
                                 XML_IS_CHAR('.')               ||      \
                                 XML_IS_RANGE('0', '9')         ||      \
                                 XML_IS_CHAR(0xB7)                      \
                                )

#define XML_NMTOKENMANY_UTF8() (                                        \
                                XML_NMTOKENMANY_ASCII()        ||       \
                                XML_IS_RANGE(0x100, 0x2FF)     ||       \
                                XML_IS_RANGE(0x370, 0x37D)     ||       \
                                XML_IS_RANGE(0x37F, 0x1FFF)    ||       \
                                XML_IS_RANGE(0x200C, 0x200D)   ||       \
                                XML_IS_RANGE(0x2070, 0x218F)   ||       \
                                XML_IS_RANGE(0x2C00, 0x2FEF)   ||       \
                                XML_IS_RANGE(0x3001, 0xD7FF)   ||       \
                                XML_IS_RANGE(0xF900, 0xFDCF)   ||       \
                                XML_IS_RANGE(0xFDF0, 0xFFFD)   ||       \
                                XML_IS_RANGE(0x10000, 0xEFFFF) ||       \
                                XML_IS_RANGE(0x0300, 0x036F)   ||       \
                                XML_IS_RANGE(0x203F, 0x2040)            \
                               )

XML_FUNC_DECL(
              is_XML_NMTOKENMANY,
              XML_NMTOKENMANY_ASCII(),
              XML_NMTOKENMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ENTITYVALUEINTERIORDQUOTEUNIT = qr{\G[^%&"]++} */
#define XML_ENTITYVALUEINTERIORDQUOTEUNIT_ASCII() (!                      \
                                                   (                      \
                                                    XML_IS_CHAR('%') ||   \
                                                    XML_IS_CHAR('&') ||   \
                                                    XML_IS_CHAR('"')      \
                                                   )                      \
                                                  )

#define XML_ENTITYVALUEINTERIORDQUOTEUNIT_UTF8()        \
  XML_ENTITYVALUEINTERIORDQUOTEUNIT_ASCII()

XML_FUNC_DECL(
              is_XML_ENTITYVALUEINTERIORDQUOTEUNIT,
              XML_ENTITYVALUEINTERIORDQUOTEUNIT_ASCII(),
              XML_ENTITYVALUEINTERIORDQUOTEUNIT_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ENTITYVALUEINTERIORSQUOTEUNIT = qr{\G[^%&']++} */
#define XML_ENTITYVALUEINTERIORSQUOTEUNIT_ASCII() (!                     \
                                                   (                     \
                                                     XML_IS_CHAR('%') || \
                                                     XML_IS_CHAR('&') || \
                                                     XML_IS_CHAR('\'')   \
                                                   )                     \
                                                  )

#define XML_ENTITYVALUEINTERIORSQUOTEUNIT_UTF8()                        \
  XML_ENTITYVALUEINTERIORSQUOTEUNIT_ASCII()

XML_FUNC_DECL(
              is_XML_ENTITYVALUEINTERIORSQUOTEUNIT,
              XML_ENTITYVALUEINTERIORSQUOTEUNIT_ASCII(),
              XML_ENTITYVALUEINTERIORSQUOTEUNIT_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ATTVALUEINTERIORDQUOTEUNIT = qr{\G[^<&"]++} */
#define XML_ATTVALUEINTERIORDQUOTEUNIT_ASCII() (!                       \
                                                (                       \
                                                 XML_IS_CHAR('<') ||    \
                                                 XML_IS_CHAR('&') ||    \
                                                 XML_IS_CHAR('"')       \
                                                )                       \
                                               )

#define XML_ATTVALUEINTERIORDQUOTEUNIT_UTF8()                           \
  XML_ATTVALUEINTERIORDQUOTEUNIT_ASCII()

XML_FUNC_DECL(
              is_XML_ATTVALUEINTERIORDQUOTEUNIT,
              XML_ATTVALUEINTERIORDQUOTEUNIT_ASCII(),
              XML_ATTVALUEINTERIORDQUOTEUNIT_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ATTVALUEINTERIORSQUOTEUNIT = qr{\G[^<&"]++} */
#define XML_ATTVALUEINTERIORSQUOTEUNIT_ASCII() (!                       \
                                                (                       \
                                                 XML_IS_CHAR('<') ||    \
                                                 XML_IS_CHAR('&') ||    \
                                                 XML_IS_CHAR('\'')      \
                                                )                       \
                                               )

#define XML_ATTVALUEINTERIORSQUOTEUNIT_UTF8()                           \
  XML_ATTVALUEINTERIORSQUOTEUNIT_ASCII()

XML_FUNC_DECL(
              is_XML_ATTVALUEINTERIORSQUOTEUNIT,
              XML_ATTVALUEINTERIORSQUOTEUNIT_ASCII(),
              XML_ATTVALUEINTERIORSQUOTEUNIT_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* NOT_DQUOTEMANY = qr{\G[^"]++} */
#define XML_NOT_DQUOTEMANY_ASCII() (!                                   \
                                    (                                   \
                                     XML_IS_CHAR('"')                   \
                                    )                                   \
                                   )

#define XML_NOT_DQUOTEMANY_UTF8() XML_NOT_DQUOTEMANY_ASCII()

XML_FUNC_DECL(
              is_XML_NOT_DQUOTEMANY,
              XML_NOT_DQUOTEMANY_ASCII(),
              XML_NOT_DQUOTEMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* NOT_SQUOTEMANY = qr{\G[^']++} */
#define XML_NOT_SQUOTEMANY_ASCII() (!                                  \
                                    (                                  \
                                     XML_IS_CHAR('\'')                 \
                                    )                                  \
                                   )

#define XML_NOT_SQUOTEMANY_UTF8() XML_NOT_SQUOTEMANY_ASCII()

XML_FUNC_DECL(
              is_XML_NOT_SQUOTEMANY,
              XML_NOT_SQUOTEMANY_ASCII(),
              XML_NOT_SQUOTEMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _CHARDATAMANY = qr{\G(?:[^<&\]]|(?:\](?!\]>)))++} # [^<&]+ without ']]>' */
#define XML_CHARDATAMANY_ASCII() (!                                     \
                                  (                                     \
                                   XML_IS_CHAR('<') ||                  \
                                   XML_IS_CHAR('&')                     \
                                  )                                     \
                                 )

#define XML_CHARDATAMANY_UTF8() XML_CHARDATAMANY_ASCII()

#define XML_CHARDATAMANY_LOOKAHEAD() (                                  \
                                      XML_IS_NOT_CHAR(']')              \
                                                                        \
                                      ||                                \
                                                                        \
                                      (!                                \
                                       _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(CHARDATAMANY_LOOKAHEAD), CHARDATAMANY_LOOKAHEAD, true) \
                                      )                                 \
                                     )

XML_FUNC_DECL(
              is_XML_CHARDATAMANY,
              XML_CHARDATAMANY_ASCII() && XML_CHARDATAMANY_LOOKAHEAD(),
              XML_CHARDATAMANY_UTF8() && XML_CHARDATAMANY_LOOKAHEAD(),
              rc,
              XML_NO_USERCODE()
              )

/* _COMMENTCHARMANY = qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{2C}\x{2E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\-(?!\-)))++}  # Char* without '--' */
#define XML_COMMENTCHARMANY_ASCII() (                                   \
                                     XML_IS_CHAR(0x9)               ||  \
                                     XML_IS_CHAR(0xA)               ||  \
                                     XML_IS_CHAR(0xD)               ||  \
                                     XML_IS_RANGE(0x20, 0xFF)           \
                                    )

#define XML_COMMENTCHARMANY_UTF8() (                                    \
                                    XML_COMMENTCHARMANY_ASCII()    ||   \
                                    XML_IS_RANGE(0x100, 0xD7FF)    ||   \
                                    XML_IS_RANGE(0xE000, 0xFFFD)   ||   \
                                    XML_IS_RANGE(0x10000, 0x10FFFF)     \
                                   )

#define XML_COMMENTCHARMANY_LOOKAHEAD() (                               \
                                         XML_IS_NOT_CHAR('-')           \
                                                                        \
                                         ||                             \
                                                                        \
                                         (!                             \
                                          _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(COMMENTCHARMANY_LOOKAHEAD), COMMENTCHARMANY_LOOKAHEAD, true) \
                                         )                              \
                                        )

XML_FUNC_DECL(
              is_XML_COMMENTCHARMANY,
              XML_COMMENTCHARMANY_ASCII() && XML_COMMENTCHARMANY_LOOKAHEAD(),
              XML_COMMENTCHARMANY_UTF8() && XML_COMMENTCHARMANY_LOOKAHEAD(),
              rc,
              XML_NO_USERCODE()
              )

/* _PITARGET => qr{\G[:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}][:A-Z_a-z\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{2FF}\x{370}-\x{37D}\x{37F}-\x{1FFF}\x{200C}-\x{200D}\x{2070}-\x{218F}\x{2C00}-\x{2FEF}\x{3001}-\x{D7FF}\x{F900}-\x{FDCF}\x{FDF0}-\x{FFFD}\x{10000}-\x{EFFFF}\-.0-9\x{B7}\x{0300}-\x{036F}\x{203F}-\x{2040}]*+}p,  # NAME but /xml/i - c.f. exclusion hash */

#define XML_PITARGET_LOOKAHEAD() (                                      \
                                  (                                     \
                                   XML_IS_NOT_CHAR('x')                 \
                                   &&                                   \
                                   XML_IS_NOT_CHAR('X')                 \
                                  )                                     \
                                                                        \
                                  ||                                    \
                                                                        \
                                  (!                                    \
                                   (                                    \
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PITARGET_LOOKAHEAD1), PITARGET_LOOKAHEAD1, false) || \
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PITARGET_LOOKAHEAD2), PITARGET_LOOKAHEAD2, false) || \
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PITARGET_LOOKAHEAD3), PITARGET_LOOKAHEAD3, false) || \
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PITARGET_LOOKAHEAD4), PITARGET_LOOKAHEAD4, false)    \
                                   )                                    \
                                  )                                     \
                                 )

/* We start the exclusion in the test: /xml/i must not match and, if it matches, this will be at first pos */
XML_FUNC_DECL(
              is_XML_PITARGET,
              XML_NAME_HEADER_ASCII() && ((rc > 0) || XML_PITARGET_LOOKAHEAD()),
              XML_NAME_HEADER_UTF8() && ((rc > 0) || XML_PITARGET_LOOKAHEAD()),
              rc,
              if (rc) {
                rc += is_XML_NAME_TRAILER(aTHX_ sv, 0, s, send);
              }
              )

/* _CDATAMANY = qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))++} # Char* minus ']]>' */
#define XML_CDATAMANY_ASCII() (                                         \
                               XML_IS_CHAR(0x9)               ||        \
                               XML_IS_CHAR(0xA)               ||        \
                               XML_IS_CHAR(0xD)               ||        \
                               XML_IS_RANGE(0x20, 0xFF)                 \
                              )

#define XML_CDATAMANY_UTF8() (                                          \
                              XML_CDATAMANY_ASCII()          ||         \
                              XML_IS_RANGE(0x100, 0xD7FF)    ||         \
                              XML_IS_RANGE(0xE000, 0xFFFD)   ||         \
                              XML_IS_RANGE(0x10000, 0x10FFFF)           \
                             )

#define XML_CDATAMANY_LOOKAHEAD() (                                     \
                                   XML_IS_NOT_CHAR(']')                 \
                                                                        \
                                   ||                                   \
                                                                        \
                                   (!                                   \
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(CDATAMANY_LOOKAHEAD), CDATAMANY_LOOKAHEAD, true) \
                                   )                                    \
                                  )

XML_FUNC_DECL(
              is_XML_CDATAMANY,
              XML_CDATAMANY_ASCII() && XML_CDATAMANY_LOOKAHEAD(),
              XML_CDATAMANY_UTF8() && XML_CDATAMANY_LOOKAHEAD(),
              rc,
              XML_NO_USERCODE()
              )

/* _CDATAMANY = qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:\](?!\]>)))++} # Char* minus ']]>' */
#define XML_PICHARDATAMANY_ASCII() (                                    \
                                    XML_IS_CHAR(0x9)               ||   \
                                    XML_IS_CHAR(0xA)               ||   \
                                    XML_IS_CHAR(0xD)               ||   \
                                    XML_IS_RANGE(0x20, 0xFF)            \
                                   )

#define XML_PICHARDATAMANY_UTF8() (                                     \
                                   XML_PICHARDATAMANY_ASCII()     ||    \
                                   XML_IS_RANGE(0x100, 0xD7FF)    ||    \
                                   XML_IS_RANGE(0xE000, 0xFFFD)   ||    \
                                   XML_IS_RANGE(0x10000, 0x10FFFF)      \
                                  )

#define XML_PICHARDATAMANY_LOOKAHEAD() (                                \
                                        XML_IS_NOT_CHAR('?')            \
                                                                        \
                                        ||                              \
                                                                        \
                                        (!                              \
                                         _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PICHARDATAMANY_LOOKAHEAD), PICHARDATAMANY_LOOKAHEAD, true) \
                                        )                               \
                                       )

XML_FUNC_DECL(
              is_XML_PICHARDATAMANY,
              XML_PICHARDATAMANY_ASCII() && XML_PICHARDATAMANY_LOOKAHEAD(),
              XML_PICHARDATAMANY_UTF8() && XML_PICHARDATAMANY_LOOKAHEAD(),
              rc,
              XML_NO_USERCODE()
              )

/* _IGNOREMANY => qr{\G(?:[\x{9}\x{A}\x{D}\x{20}-\x{3B}\x{3D}-\x{5C}\x{5E}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]|(?:<(?!!\[))|(?:\](?!\]>)))++} # Char minus* ('<![' or ']]>') */
#define XML_IGNOREMANY_ASCII() (                                        \
                                XML_IS_CHAR(0x9)               ||       \
                                XML_IS_CHAR(0xA)               ||       \
                                XML_IS_CHAR(0xD)               ||       \
                                XML_IS_RANGE(0x20, 0xFF)                \
                               )

#define XML_IGNOREMANY_UTF8() (                                         \
                               XML_IGNOREMANY_ASCII()         ||        \
                               XML_IS_RANGE(0x100, 0xD7FF)    ||        \
                               XML_IS_RANGE(0xE000, 0xFFFD)   ||        \
                               XML_IS_RANGE(0x10000, 0x10FFFF)          \
                              )

#define XML_IGNOREMANY_LOOKAHEAD() (                                    \
                                    (                                   \
                                     XML_IS_NOT_CHAR('<')               \
                                     &&                                 \
                                     XML_IS_NOT_CHAR(']')               \
                                    )                                   \
                                                                        \
                                    ||                                  \
                                                                        \
                                    (                                   \
                                     XML_IS_CHAR('<')                   \
                                     ?                                  \
                                     (!                                 \
                                      _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(IGNOREMANY_LOOKAHEAD1), IGNOREMANY_LOOKAHEAD1, true) \
                                     )                                  \
                                     :                                  \
                                     (!                                 \
                                      _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(IGNOREMANY_LOOKAHEAD2), IGNOREMANY_LOOKAHEAD2, true) \
                                     )                                  \
                                    )                                   \
                                   )

XML_FUNC_DECL(
              is_XML_IGNOREMANY,
              XML_IGNOREMANY_ASCII() && XML_IGNOREMANY_LOOKAHEAD(),
              XML_IGNOREMANY_UTF8() && XML_IGNOREMANY_LOOKAHEAD(),
              rc,
              XML_NO_USERCODE()
              )

/* _DIGITMANY => qr{\G[0-9]++} */
#define XML_DIGITMANY_ASCII()                   \
  XML_IS_RANGE('0', '9')

#define XML_DIGITMANY_UTF8()                    \
  XML_DIGITMANY_ASCII()

XML_FUNC_DECL(
              is_XML_DIGITMANY,
              XML_DIGITMANY_ASCII(),
              XML_DIGITMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ALPHAMANY => qr{\G[0-9a-fA-F]++} */
#define XML_ALPHAMANY_ASCII() (                                         \
                               XML_IS_RANGE('0', '9') ||                \
                               XML_IS_RANGE('a', 'f') ||                \
                               XML_IS_RANGE('A', 'F')                   \
                              )

#define XML_ALPHAMANY_UTF8()                    \
  XML_ALPHAMANY_ASCII()

XML_FUNC_DECL(
              is_XML_ALPHAMANY,
              XML_ALPHAMANY_ASCII(),
              XML_ALPHAMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _ENCNAME => qr{\G[A-Za-z][A-Za-z0-9._\-]*+} */
#define XML_ENCNAME_TRAILER_ASCII() (                                   \
                                     XML_IS_RANGE('A', 'Z')         ||  \
                                     XML_IS_RANGE('a', 'z')         ||  \
                                     XML_IS_RANGE('0', '9')         ||  \
                                     XML_IS_CHAR('.')               ||  \
                                     XML_IS_CHAR('_')               ||  \
                                     XML_IS_CHAR('-')                   \
                                    )

#define XML_ENCNAME_TRAILER_UTF8()              \
  XML_ENCNAME_TRAILER_ASCII()

XML_FUNC_DECL(
              is_XML_ENCNAME_TRAILER,
              XML_ENCNAME_TRAILER_ASCII(),
              XML_ENCNAME_TRAILER_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

#define XML_ENCNAME_HEADER_ASCII() (                                    \
                                    XML_IS_RANGE('A', 'Z')         ||   \
                                    XML_IS_RANGE('a', 'z')              \
                                   )

#define XML_ENCNAME_HEADER_UTF8()               \
  XML_ENCNAME_HEADER_ASCII()

XML_FUNC_DECL(
              is_XML_ENCNAME,
              XML_ENCNAME_HEADER_ASCII(),
              XML_ENCNAME_HEADER_UTF8(), 
              rc,
              if (rc) {
                rc += is_XML_ENCNAME_TRAILER(aTHX_ sv, 0, s, send);
              }
              )

/* _S => qr{\G[\x{20}\x{9}\x{D}\x{A}]++} */

#define XML_S_ASCII() (                                                 \
                       XML_IS_CHAR(0x20) ||                             \
                       XML_IS_CHAR(0x9) ||                              \
                       XML_IS_CHAR(0xD) ||                              \
                       XML_IS_CHAR(0xA)                                 \
                      )

#define XML_S_UTF8()                            \
  XML_S_ASCII()

XML_FUNC_DECL(
              is_XML_S,
              XML_S_ASCII(),
              XML_S_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* _NCNAME = qr/\G${_NAME_WITHOUT_COLON_REGEXP}(?=(?::${_NAME_WITHOUT_COLON_REGEXP}[^:])|[^:]) */

#define XML_NCNAME_LOOKAHEAD() (is_XML_COLON_NAME_WITHOUT_COLON(aTHX_ sv, 0, s+ulen, send)

XML_FUNC_DECL(is_XML_NCNAME,
              XML_NAME_WITHOUT_COLON_HEADER_ASCII(),
              XML_NAME_WITHOUT_COLON_HEADER_UTF8(),
              rc,
              if (rc) {
                UV colon[] = { ':' };
                if ((! is_XML_COLON_THEN_NAME_WITHOUT_COLON_THEN_NOCOLON(aTHX_ sv, 0, s, send))
                    &&
                    _is_XML_STRING(aTHX_ sv, 0, s, send, 1, colon, true)
                    ) {
                  rc = 0;
                }
              }
              )

/* ======================================================================= */
/*                                 XML 1.0                                 */
/* ======================================================================= */
XML_FUNC_ALIAS(is_XML10_NAME,                          is_XML_NAME)
XML_FUNC_ALIAS(is_XML10_NMTOKENMANY,                   is_XML_NMTOKENMANY)
XML_FUNC_ALIAS(is_XML10_ENTITYVALUEINTERIORDQUOTEUNIT, is_XML_ENTITYVALUEINTERIORDQUOTEUNIT)
XML_FUNC_ALIAS(is_XML10_ENTITYVALUEINTERIORSQUOTEUNIT, is_XML_ENTITYVALUEINTERIORSQUOTEUNIT)
XML_FUNC_ALIAS(is_XML10_ATTVALUEINTERIORDQUOTEUNIT,    is_XML_ATTVALUEINTERIORDQUOTEUNIT)
XML_FUNC_ALIAS(is_XML10_ATTVALUEINTERIORSQUOTEUNIT,    is_XML_ATTVALUEINTERIORSQUOTEUNIT)
XML_FUNC_ALIAS(is_XML10_NOT_DQUOTEMANY,                is_XML_NOT_DQUOTEMANY)
XML_FUNC_ALIAS(is_XML10_NOT_SQUOTEMANY,                is_XML_NOT_SQUOTEMANY)
XML_FUNC_ALIAS(is_XML10_CHARDATAMANY,                  is_XML_CHARDATAMANY)
XML_FUNC_ALIAS(is_XML10_COMMENTCHARMANY,               is_XML_COMMENTCHARMANY)
XML_FUNC_ALIAS(is_XML10_PITARGET,                      is_XML_PITARGET)
XML_FUNC_ALIAS(is_XML10_CDATAMANY,                     is_XML_CDATAMANY)
XML_FUNC_ALIAS(is_XML10_PICHARDATAMANY,                is_XML_PICHARDATAMANY)
XML_FUNC_ALIAS(is_XML10_IGNOREMANY,                    is_XML_IGNOREMANY)
XML_FUNC_ALIAS(is_XML10_DIGITMANY,                     is_XML_DIGITMANY)
XML_FUNC_ALIAS(is_XML10_ALPHAMANY,                     is_XML_ALPHAMANY)
XML_FUNC_ALIAS(is_XML10_ENCNAME,                       is_XML_ENCNAME)
XML_FUNC_ALIAS(is_XML10_NCNAME,                        is_XML_NCNAME)
XML_FUNC_ALIAS(is_XML10_S,                             is_XML_S)

/* ======================================================================= */
/*                                 XML 1.1                                 */
/* ======================================================================= */
XML_FUNC_ALIAS(is_XML11_NAME,                          is_XML_NAME)
XML_FUNC_ALIAS(is_XML11_NMTOKENMANY,                   is_XML_NMTOKENMANY)
XML_FUNC_ALIAS(is_XML11_ENTITYVALUEINTERIORDQUOTEUNIT, is_XML_ENTITYVALUEINTERIORDQUOTEUNIT)
XML_FUNC_ALIAS(is_XML11_ENTITYVALUEINTERIORSQUOTEUNIT, is_XML_ENTITYVALUEINTERIORSQUOTEUNIT)
XML_FUNC_ALIAS(is_XML11_ATTVALUEINTERIORDQUOTEUNIT,    is_XML_ATTVALUEINTERIORDQUOTEUNIT)
XML_FUNC_ALIAS(is_XML11_ATTVALUEINTERIORSQUOTEUNIT,    is_XML_ATTVALUEINTERIORSQUOTEUNIT)
XML_FUNC_ALIAS(is_XML11_NOT_DQUOTEMANY,                is_XML_NOT_DQUOTEMANY)
XML_FUNC_ALIAS(is_XML11_NOT_SQUOTEMANY,                is_XML_NOT_SQUOTEMANY)
XML_FUNC_ALIAS(is_XML11_CHARDATAMANY,                  is_XML_CHARDATAMANY)
XML_FUNC_ALIAS(is_XML11_COMMENTCHARMANY,               is_XML_COMMENTCHARMANY)
XML_FUNC_ALIAS(is_XML11_PITARGET,                      is_XML_PITARGET)
XML_FUNC_ALIAS(is_XML11_CDATAMANY,                     is_XML_CDATAMANY)
XML_FUNC_ALIAS(is_XML11_PICHARDATAMANY,                is_XML_PICHARDATAMANY)
XML_FUNC_ALIAS(is_XML11_IGNOREMANY,                    is_XML_IGNOREMANY)
XML_FUNC_ALIAS(is_XML11_DIGITMANY,                     is_XML_DIGITMANY)
XML_FUNC_ALIAS(is_XML11_ALPHAMANY,                     is_XML_ALPHAMANY)
XML_FUNC_ALIAS(is_XML11_ENCNAME,                       is_XML_ENCNAME)
XML_FUNC_ALIAS(is_XML11_NCNAME,                        is_XML_NCNAME)
XML_FUNC_ALIAS(is_XML11_S,                             is_XML_S)

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

STRLEN
is_XML10_NMTOKENMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NMTOKENMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NMTOKENMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NMTOKENMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITYVALUEINTERIORDQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITYVALUEINTERIORDQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITYVALUEINTERIORDQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITYVALUEINTERIORDQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITYVALUEINTERIORSQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITYVALUEINTERIORSQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITYVALUEINTERIORSQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITYVALUEINTERIORSQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ATTVALUEINTERIORDQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ATTVALUEINTERIORDQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ATTVALUEINTERIORDQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ATTVALUEINTERIORDQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ATTVALUEINTERIORSQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ATTVALUEINTERIORSQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ATTVALUEINTERIORSQUOTEUNIT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ATTVALUEINTERIORSQUOTEUNIT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOT_DQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOT_DQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOT_DQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOT_DQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOT_SQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOT_SQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOT_SQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOT_SQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHARDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHARDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHARDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHARDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_COMMENTCHARMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_COMMENTCHARMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_COMMENTCHARMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_COMMENTCHARMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PITARGET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PITARGET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PITARGET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PITARGET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PICHARDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PICHARDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PICHARDATAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PICHARDATAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNOREMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNOREMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNOREMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNOREMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_DIGITMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_DIGITMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_DIGITMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_DIGITMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ALPHAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ALPHAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ALPHAMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ALPHAMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENCNAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENCNAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENCNAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENCNAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NCNAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NCNAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NCNAME(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NCNAME(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL
