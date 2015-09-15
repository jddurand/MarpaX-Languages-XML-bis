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
#define XML_PRINT_FUNC_EXCLUSION(funcname)                              \
  do {                                                                  \
    fprintf(stderr, "%s matches exclusion\n", #funcname);               \
  } while (0)
#else
#define XML_PRINT_CHAR_STATUS(funcname, ch, status)
#define XML_PRINT_FUNC_STATUS(funcname, retval)
#define XML_PRINT_FUNC_EXCLUSION(funcname)
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

#define XML_STRING_DECL(stringname)                                     \
static                                                                  \
STRLEN is_XML_##stringname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) { \
  return _is_XML_STRING(aTHX_ sv, pos, s_force, send_force, XML_ARRAY_LENGTH(XML_##stringname##_STRING), XML_##stringname##_STRING); \
}
#define XML10_STRING_DECL(stringname)                                     \
static                                                                  \
STRLEN is_XML10_##stringname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) { \
  return _is_XML_STRING(aTHX_ sv, pos, s_force, send_force, XML_ARRAY_LENGTH(XML10_##stringname##_STRING), XML10_##stringname##_STRING); \
}
#define XML11_STRING_DECL(stringname)                                     \
static                                                                  \
STRLEN is_XML11_##stringname(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force) { \
  return _is_XML_STRING(aTHX_ sv, pos, s_force, send_force, XML_ARRAY_LENGTH(XML11_##stringname##_STRING), XML11_##stringname##_STRING); \
}

/* ======================================================================= */
/*              Static definitions used for lookaheads                     */
/* ======================================================================= */
static UV CHARDATAMANY_LOOKAHEAD[]    = { /* ']', */ ']', '>' };
static UV COMMENTCHARMANY_LOOKAHEAD[] = { /* '-', */ '-'      };
static UV CDATAMANY_LOOKAHEAD[]       = { /* ']', */ ']', '>' };
static UV PICHARDATAMANY_LOOKAHEAD[]  = { /* '?', */ '>'      };
static UV IGNOREMANY_LOOKAHEAD1[]     = { /* '<', */ '!', '[' };
static UV IGNOREMANY_LOOKAHEAD2[]     = { /* ']', */ ']', '>' };

/* ======================================================================= */
/*              Static definitions used for exclusions                     */
/* ======================================================================= */
#define PITARGET_EXCLUSION_LENGTH 3
static UV PITARGET_EXCLUSION_UPPERCASE[PITARGET_EXCLUSION_LENGTH] = { 'X', 'M', 'L' };
static UV PITARGET_EXCLUSION_LOWERCASE[PITARGET_EXCLUSION_LENGTH] = { 'x', 'm', 'l' };

/* ======================================================================= */
/*                  Static definitions for strings                         */
/* ======================================================================= */
static UV XML_SPACE_STRING[]                        = { 0x020                                            };
static UV XML_DQUOTE_STRING[]                       = { '"'                                              };
static UV XML_SQUOTE_STRING[]                       = { '\''                                             };
static UV XML_COMMENT_START_STRING[]                = { '<', '!', '-', '-'                               };
static UV XML_COMMENT_END_STRING[]                  = { '-', '-', '>'                                    };
static UV XML_PI_START_STRING[]                     = { '<', '?'                                         };
static UV XML_PI_END_STRING[]                       = { '?', '>'                                         };
static UV XML_CDATA_START_STRING[]                  = { '!', '[', 'C', 'D', 'A', 'T', 'A', '['           };
static UV XML_CDATA_END_STRING[]                    = { ']', ']', '>'                                    };
static UV XML_XMLDECL_START_STRING[]                = { '<', '?', 'x', 'm', 'l'                          };
static UV XML_XMLDECL_END_STRING[]                  = { '?', '>'                                         };
static UV XML_VERSION_STRING[]                      = { 'v', 'e', 'r', 's', 'i', 'o', 'n'                };
static UV XML_EQUAL_STRING[]                        = { '='                                              };
static UV XML10_VERSIONNUM_STRING[]                 = { '1', '.', '0'                                    };
static UV XML11_VERSIONNUM_STRING[]                 = { '1', '.', '1'                                    };
static UV XML_ANY_STRING[]                          = { 'A', 'N', 'Y'                                    };
static UV XML_ATTLIST_END_STRING[]                  = { '>'                                              };
static UV XML_ATTLIST_START_STRING[]                = { '<', '!', 'A', 'T', 'T', 'L', 'I', 'S', 'T'      };
static UV XML_CDATA_STRING[]                        = { 'C', 'D', 'A', 'T', 'A'                          };
static UV XML_CHARREF_END1_STRING[]                 = { ';'                                              };
static UV XML_CHARREF_END2_STRING[]                 = { ';'                                              };
static UV XML_CHARREF_START1_STRING[]               = { '&', '#'                                         };
static UV XML_CHARREF_START2_STRING[]               = { '&', '#', 'x'                                    };
static UV XML_CHOICE_END_STRING[]                   = { ')'                                              };
static UV XML_CHOICE_START_STRING[]                 = { '('                                              };
static UV XML_COLON_STRING[]                        = { ':'                                              };
static UV XML_COMMA_STRING[]                        = { ','                                              };
static UV XML_DOCTYPE_END_STRING[]                  = { '>'                                              };
static UV XML_DOCTYPE_START_STRING[]                = { '<', '!', 'D', 'O', 'C', 'T', 'Y', 'P', 'E'      };
static UV XML_ELEMENTDECL_END_STRING[]              = { '>'                                              };
static UV XML_ELEMENTDECL_START_STRING[]            = { '<', '!', 'E', 'L', 'E', 'M', 'E', 'N', 'T'      };
static UV XML_ELEMENT_END_STRING[]                  = { '>'                                              };
static UV XML_ELEMENT_START_STRING[]                = { '<'                                              };
static UV XML_EMPTY_STRING[]                        = { 'E', 'M', 'P', 'T', 'Y'                          };
static UV XML_EMPTYELEM_END_STRING[]                = { '/', '>'                                         };
static UV XML_ENCODING_STRING[]                     = { 'e', 'n', 'c', 'o', 'd', 'i', 'n', 'g'           };
static UV XML_ENTITIES_STRING[]                     = { 'E', 'N', 'T', 'I', 'T', 'I', 'E', 'S'           };
static UV XML_ENTITY_STRING[]                       = { 'E', 'N', 'T', 'I', 'T', 'Y'                     };
static UV XML_ENTITYREF_END_STRING[]                = { ';'                                              };
static UV XML_ENTITYREF_START_STRING[]              = { '&'                                              };
static UV XML_ENTITY_END_STRING[]                   = { '>'                                              };
static UV XML_ENTITY_START_STRING[]                 = { '<', '!', 'E', 'N', 'T', 'I', 'T', 'Y'           };
static UV XML_ENUMERATION_END_STRING[]              = { ')'                                              };
static UV XML_ENUMERATION_START_STRING[]            = { '('                                              };
static UV XML_ETAG_END_STRING[]                     = { '>'                                              };
static UV XML_ETAG_START_STRING[]                   = { '<', '/'                                         };
static UV XML_FIXED_STRING[]                        = { '#', 'F', 'I', 'X', 'E', 'D'                     };
static UV XML_ID_STRING[]                           = { 'I', 'D'                                         };
static UV XML_IDREF_STRING[]                        = { 'I', 'D', 'R', 'E', 'F'                          };
static UV XML_IDREFS_STRING[]                       = { 'I', 'D', 'R', 'E', 'F', 'S'                     };
static UV XML_IGNORE_STRING[]                       = { 'I', 'G', 'N', 'O', 'R', 'E'                     };
static UV XML_IGNORESECTCONTENTSUNIT_END_STRING[]   = { ']', ']', '>'                                    };
static UV XML_IGNORESECTCONTENTSUNIT_START_STRING[] = { '<', '!', '['                                    };
static UV XML_IGNORESECT_END_STRING[]               = { ']', ']', '>'                                    };
static UV XML_IGNORESECT_START_STRING[]             = { '<', '!', '['                                    };
static UV XML_IMPLIED_STRING[]                      = { '#', 'I', 'M', 'P', 'L', 'I', 'E', 'D'           };
static UV XML_INCLUDE_STRING[]                      = { 'I', 'N', 'C', 'L', 'U', 'D', 'E'                };
static UV XML_INCLUDESECT_END_STRING[]              = { ']', ']', '>'                                    };
static UV XML_INCLUDESECT_START_STRING[]            = { '<', '!', '['                                    };
static UV XML_LBRACKET_STRING[]                     = { '['                                              };
static UV XML_MIXED_END1_STRING[]                   = { ')', '*'                                         };
static UV XML_MIXED_END2_STRING[]                   = { ')'                                              };
static UV XML_MIXED_START_STRING[]                  = { '('                                              };
static UV XML_NDATA_STRING[]                        = { 'N', 'D', 'A', 'T', 'A'                          };
static UV XML_NMTOKEN_STRING[]                      = { 'N', 'M', 'T', 'O', 'K', 'E', 'N'                };
static UV XML_NMTOKENS_STRING[]                     = { 'N', 'M', 'T', 'O', 'K', 'E', 'N', 'S'           };
static UV XML_NO_STRING[]                           = { 'n', 'o'                                         };
static UV XML_NOTATION_STRING[]                     = { 'N', 'O', 'T', 'A', 'T', 'I', 'O', 'N'           };
static UV XML_NOTATIONDECL_END_STRING[]             = { '>'                                              };
static UV XML_NOTATIONDECL_START_STRING[]           = { '<', '!', 'N', 'O', 'T', 'A', 'T', 'I', 'O', 'N' };
static UV XML_NOTATION_END_STRING[]                 = { ')'                                              };
static UV XML_NOTATION_START_STRING[]               = { '('                                              };
static UV XML_OR_STRING[]                           = { '|'                                              };
static UV XML_PCDATA_STRING[]                       = { '#', 'P', 'C', 'D', 'A', 'T', 'A'                };
static UV XML_PERCENT_STRING[]                      = { '%'                                              };
static UV XML_PEREFERENCE_END_STRING[]              = { ';'                                              };
static UV XML_PEREFERENCE_START_STRING[]            = { '%'                                              };
static UV XML_PLUS_STRING[]                         = { '+'                                              };
static UV XML_PUBLIC_STRING[]                       = { 'P', 'U', 'B', 'L', 'I', 'C'                     };
static UV XML_QUESTIONMARK_STRING[]                 = { '?'                                              };
static UV XML_RBRACKET_STRING[]                     = { ']'                                              };
static UV XML_REQUIRED_STRING[]                     = { '#', 'R', 'E', 'Q', 'U', 'I', 'R', 'E', 'D'      };
static UV XML_SEQ_END_STRING[]                      = { ')'                                              };
static UV XML_SEQ_START_STRING[]                    = { '('                                              };
static UV XML_STANDALONE_STRING[]                   = { 's', 't', 'a', 'n', 'd', 'a', 'l', 'o', 'n', 'e' };
static UV XML_STAR_STRING[]                         = { '*'                                              };
static UV XML_SYSTEM_STRING[]                       = { 'S', 'Y', 'S', 'T', 'E', 'M'                     };
static UV XML_TEXTDECL_END_STRING[]                 = { '?', '>'                                         };
static UV XML_TEXTDECL_START_STRING[]               = { '<', '?', 'x', 'm', 'l'                          };
static UV XML_YES_STRING[]                          = { 'y', 'e', 's'                                    };

/* ======================================================================= */
/*          Internal function used to search for a string                  */
/* ======================================================================= */
static
STRLEN _is_XML_STRING(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force, STRLEN nuv, UV string[]) {
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

  if (retval != nuv) {
    /* sv does not start with string */
    retval = 0;
  }

  XML_PRINT_FUNC_STATUS(_is_XML_STRING, retval);                                 \
  return retval;
}

/* ======================================================================= */
/*          Internal function used to search for a string                  */
/*      The caller must give two UV[] for case insensitivity               */
/* ======================================================================= */
static
STRLEN _is_XML_STRING_INSENSITIVE(pTHX_ SV *sv, STRLEN pos, U8 *s_force, U8 *send_force, STRLEN nuv, UV uppercase[], UV lowercase[]) {
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
      if ((uppercase[i] == (UV)ch) || (lowercase[i] == (UV)ch)) {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING_INSENSITIVE, ch, "ok (ASCII mode)");
        retval++;
        s++;
        i++;
      } else {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING_INSENSITIVE, ch, "ko (ASCII mode)");
        break;
      }
    }
  } else {
    if (pos) {
      s = utf8_hop(s, pos);
    }
    while ((i < nuv) && (s < send)) {
      UV ch = NATIVE_TO_UNI(utf8_to_uvchr_buf(s, send, &ulen));
      if ((uppercase[i] == (UV)ch) || (lowercase[i] == (UV)ch)) {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING_INSENSITIVE, ch, "ok (UTF8 mode)");
        retval++;
        s += ulen;
        i++;
      } else {
        XML_PRINT_CHAR_STATUS(_is_XML_STRING_INSENSITIVE, ch, "ko (UTF8 mode)");
        break;
      }
    }
  }

  if (retval != nuv) {
    /* sv does not start with string (case insensitive) */
    retval = 0;
  }

  XML_PRINT_FUNC_STATUS(_is_XML_STRING_INSENSITIVE, retval);                                 \
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
                if (_is_XML_STRING(aTHX_ sv, 0, s, send, 1, colon)) {
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
                UV colon[] = { ':' };
                if (_is_XML_STRING(aTHX_ sv, 0, s, send, 1, colon)) {
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
                                       _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(CHARDATAMANY_LOOKAHEAD), CHARDATAMANY_LOOKAHEAD) \
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
                                          _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(COMMENTCHARMANY_LOOKAHEAD), COMMENTCHARMANY_LOOKAHEAD) \
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

/* We start the exclusion in the test: /xml/i must not match and, if it matches, this will be at first pos */
XML_FUNC_DECL(
              is_XML_PITARGET,
              XML_NAME_HEADER_ASCII(),
              XML_NAME_HEADER_UTF8(),
              rc,
              if (rc) {
                rc += is_XML_NAME_TRAILER(aTHX_ sv, 0, s, send);
              }
              if ((rc == PITARGET_EXCLUSION_LENGTH) && _is_XML_STRING_INSENSITIVE(aTHX_ sv, pos, NULL, NULL, PITARGET_EXCLUSION_LENGTH, PITARGET_EXCLUSION_UPPERCASE, PITARGET_EXCLUSION_LOWERCASE)) {
                XML_PRINT_FUNC_EXCLUSION(is_XML_PITARGET);
                rc = 0;
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
                                    _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(CDATAMANY_LOOKAHEAD), CDATAMANY_LOOKAHEAD) \
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
                                         _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(PICHARDATAMANY_LOOKAHEAD), PICHARDATAMANY_LOOKAHEAD) \
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
                                      _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(IGNOREMANY_LOOKAHEAD1), IGNOREMANY_LOOKAHEAD1) \
                                     )                                  \
                                     :                                  \
                                     (!                                 \
                                      _is_XML_STRING(aTHX_ sv, 0, s+ulen, send, XML_ARRAY_LENGTH(IGNOREMANY_LOOKAHEAD2), IGNOREMANY_LOOKAHEAD2) \
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
                STRLEN rc2 = is_XML_COLON_THEN_NAME_WITHOUT_COLON_THEN_NOCOLON(aTHX_ sv, 0, s, send);
                if (rc2) {
                  rc += rc2;
                } else if (_is_XML_STRING(aTHX_ sv, 0, s, send, 1, colon)) {
                  rc = 0;
                }
              }
              )

/* _PUBIDCHARDQUOTEMANY = qr{\G[a-zA-Z0-9\-'()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++} */
#define XML_PUBIDCHARDQUOTEMANY_ASCII() (                               \
                                     XML_IS_RANGE('a', 'z') ||          \
                                     XML_IS_RANGE('A', 'Z') ||          \
                                     XML_IS_RANGE('0', '9') ||          \
                                     XML_IS_CHAR('-')       ||          \
                                     XML_IS_CHAR('\'')      ||          \
                                     XML_IS_CHAR('(')       ||          \
                                     XML_IS_CHAR(')')       ||          \
                                     XML_IS_CHAR('+')       ||          \
                                     XML_IS_CHAR(',')       ||          \
                                     XML_IS_CHAR('.')       ||          \
                                     XML_IS_CHAR('/')       ||          \
                                     XML_IS_CHAR(':')       ||          \
                                     XML_IS_CHAR('=')       ||          \
                                     XML_IS_CHAR('?')       ||          \
                                     XML_IS_CHAR(';')       ||          \
                                     XML_IS_CHAR('!')       ||          \
                                     XML_IS_CHAR('*')       ||          \
                                     XML_IS_CHAR('#')       ||          \
                                     XML_IS_CHAR('@')       ||          \
                                     XML_IS_CHAR('$')       ||          \
                                     XML_IS_CHAR('_')       ||          \
                                     XML_IS_CHAR('%')       ||          \
                                     XML_IS_CHAR(0x20)      ||          \
                                     XML_IS_CHAR(0xD)       ||          \
                                     XML_IS_CHAR(0xA)                   \
                                    )

#define XML_PUBIDCHARDQUOTEMANY_UTF8()        \
  XML_PUBIDCHARDQUOTEMANY_ASCII()

XML_FUNC_DECL(
              is_XML_PUBIDCHARDQUOTEMANY,
              XML_PUBIDCHARDQUOTEMANY_ASCII(),
              XML_PUBIDCHARDQUOTEMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )


/* _PUBIDCHARSQUOTEMANY = qr{\G[a-zA-Z0-9\-()+,./:=?;!*#@\$_%\x{20}\x{D}\x{A}]++} */
#define XML_PUBIDCHARSQUOTEMANY_ASCII() (                               \
                                     XML_IS_RANGE('a', 'z') ||          \
                                     XML_IS_RANGE('A', 'Z') ||          \
                                     XML_IS_RANGE('0', '9') ||          \
                                     XML_IS_CHAR('-')       ||          \
                                     XML_IS_CHAR('\'')      ||          \
                                     XML_IS_CHAR('(')       ||          \
                                     XML_IS_CHAR(')')       ||          \
                                     XML_IS_CHAR('+')       ||          \
                                     XML_IS_CHAR(',')       ||          \
                                     XML_IS_CHAR('.')       ||          \
                                     XML_IS_CHAR('/')       ||          \
                                     XML_IS_CHAR(':')       ||          \
                                     XML_IS_CHAR('=')       ||          \
                                     XML_IS_CHAR('?')       ||          \
                                     XML_IS_CHAR(';')       ||          \
                                     XML_IS_CHAR('!')       ||          \
                                     XML_IS_CHAR('*')       ||          \
                                     XML_IS_CHAR('#')       ||          \
                                     XML_IS_CHAR('@')       ||          \
                                     XML_IS_CHAR('$')       ||          \
                                     XML_IS_CHAR('_')       ||          \
                                     XML_IS_CHAR('%')       ||          \
                                     XML_IS_CHAR(0x20)      ||          \
                                     XML_IS_CHAR(0xD)       ||          \
                                     XML_IS_CHAR(0xA)                   \
                                    )

#define XML_PUBIDCHARSQUOTEMANY_UTF8()        \
  XML_PUBIDCHARSQUOTEMANY_ASCII()

XML_FUNC_DECL(
              is_XML_PUBIDCHARSQUOTEMANY,
              XML_PUBIDCHARSQUOTEMANY_ASCII(),
              XML_PUBIDCHARSQUOTEMANY_UTF8(),
              rc,
              XML_NO_USERCODE()
              )

/* Fixed strings */
XML_STRING_DECL(SPACE)
XML_STRING_DECL(DQUOTE)
XML_STRING_DECL(SQUOTE)
XML_STRING_DECL(COMMENT_START)
XML_STRING_DECL(COMMENT_END)
XML_STRING_DECL(PI_START)
XML_STRING_DECL(PI_END)
XML_STRING_DECL(CDATA_START)
XML_STRING_DECL(CDATA_END)
XML_STRING_DECL(XMLDECL_START)
XML_STRING_DECL(XMLDECL_END)
XML_STRING_DECL(VERSION)
XML_STRING_DECL(EQUAL)
XML10_STRING_DECL(VERSIONNUM)
XML11_STRING_DECL(VERSIONNUM)
XML_STRING_DECL(ANY)
XML_STRING_DECL(ATTLIST_END)
XML_STRING_DECL(ATTLIST_START)
XML_STRING_DECL(CDATA)
XML_STRING_DECL(CHARREF_END1)
XML_STRING_DECL(CHARREF_END2)
XML_STRING_DECL(CHARREF_START1)
XML_STRING_DECL(CHARREF_START2)
XML_STRING_DECL(CHOICE_END)
XML_STRING_DECL(CHOICE_START)
XML_STRING_DECL(COLON)
XML_STRING_DECL(COMMA)
XML_STRING_DECL(DOCTYPE_END)
XML_STRING_DECL(DOCTYPE_START)
XML_STRING_DECL(ELEMENTDECL_END)
XML_STRING_DECL(ELEMENTDECL_START)
XML_STRING_DECL(ELEMENT_END)
XML_STRING_DECL(ELEMENT_START)
XML_STRING_DECL(EMPTY)
XML_STRING_DECL(EMPTYELEM_END)
XML_STRING_DECL(ENCODING)
XML_STRING_DECL(ENTITIES)
XML_STRING_DECL(ENTITY)
XML_STRING_DECL(ENTITYREF_END)
XML_STRING_DECL(ENTITYREF_START)
XML_STRING_DECL(ENTITY_END)
XML_STRING_DECL(ENTITY_START)
XML_STRING_DECL(ENUMERATION_END)
XML_STRING_DECL(ENUMERATION_START)
XML_STRING_DECL(ETAG_END)
XML_STRING_DECL(ETAG_START)
XML_STRING_DECL(FIXED)
XML_STRING_DECL(ID)
XML_STRING_DECL(IDREF)
XML_STRING_DECL(IDREFS)
XML_STRING_DECL(IGNORE)
XML_STRING_DECL(IGNORESECTCONTENTSUNIT_END)
XML_STRING_DECL(IGNORESECTCONTENTSUNIT_START)
XML_STRING_DECL(IGNORESECT_END)
XML_STRING_DECL(IGNORESECT_START)
XML_STRING_DECL(IMPLIED)
XML_STRING_DECL(INCLUDE)
XML_STRING_DECL(INCLUDESECT_END)
XML_STRING_DECL(INCLUDESECT_START)
XML_STRING_DECL(LBRACKET)
XML_STRING_DECL(MIXED_END1)
XML_STRING_DECL(MIXED_END2)
XML_STRING_DECL(MIXED_START)
XML_STRING_DECL(NDATA)
XML_STRING_DECL(NMTOKEN)
XML_STRING_DECL(NMTOKENS)
XML_STRING_DECL(NO)
XML_STRING_DECL(NOTATION)
XML_STRING_DECL(NOTATIONDECL_END)
XML_STRING_DECL(NOTATIONDECL_START)
XML_STRING_DECL(NOTATION_END)
XML_STRING_DECL(NOTATION_START)
XML_STRING_DECL(OR)
XML_STRING_DECL(PCDATA)
XML_STRING_DECL(PERCENT)
XML_STRING_DECL(PEREFERENCE_END)
XML_STRING_DECL(PEREFERENCE_START)
XML_STRING_DECL(PLUS)
XML_STRING_DECL(PUBLIC)
XML_STRING_DECL(QUESTIONMARK)
XML_STRING_DECL(RBRACKET)
XML_STRING_DECL(REQUIRED)
XML_STRING_DECL(SEQ_END)
XML_STRING_DECL(SEQ_START)
XML_STRING_DECL(STANDALONE)
XML_STRING_DECL(STAR)
XML_STRING_DECL(SYSTEM)
XML_STRING_DECL(TEXTDECL_END)
XML_STRING_DECL(TEXTDECL_START)
XML_STRING_DECL(YES)

/* ======================================================================= */
/*                                 XML 1.0                                 */
/*           These symbols map to a method common between 1.0 and 1.1      */
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
XML_FUNC_ALIAS(is_XML10_PUBIDCHARDQUOTEMANY,           is_XML_PUBIDCHARDQUOTEMANY)
XML_FUNC_ALIAS(is_XML10_PUBIDCHARSQUOTEMANY,           is_XML_PUBIDCHARSQUOTEMANY)
XML_FUNC_ALIAS(is_XML10_SPACE,                         is_XML_SPACE)
XML_FUNC_ALIAS(is_XML10_DQUOTE,                        is_XML_DQUOTE)
XML_FUNC_ALIAS(is_XML10_SQUOTE,                        is_XML_SQUOTE)
XML_FUNC_ALIAS(is_XML10_COMMENT_START,                 is_XML_COMMENT_START)
XML_FUNC_ALIAS(is_XML10_COMMENT_END,                   is_XML_COMMENT_END)
XML_FUNC_ALIAS(is_XML10_PI_START,                      is_XML_PI_START)
XML_FUNC_ALIAS(is_XML10_PI_END,                        is_XML_PI_END)
XML_FUNC_ALIAS(is_XML10_CDATA_START,                   is_XML_CDATA_START)
XML_FUNC_ALIAS(is_XML10_CDATA_END,                     is_XML_CDATA_END)
XML_FUNC_ALIAS(is_XML10_XMLDECL_START,                 is_XML_XMLDECL_START)
XML_FUNC_ALIAS(is_XML10_XMLDECL_END,                   is_XML_XMLDECL_END)
XML_FUNC_ALIAS(is_XML10_VERSION,                       is_XML_VERSION)
XML_FUNC_ALIAS(is_XML10_EQUAL,                         is_XML_EQUAL)
XML_FUNC_ALIAS(is_XML10_ANY,                           is_XML_ANY)
XML_FUNC_ALIAS(is_XML10_ATTLIST_END,                   is_XML_ATTLIST_END)
XML_FUNC_ALIAS(is_XML10_ATTLIST_START,                 is_XML_ATTLIST_START)
XML_FUNC_ALIAS(is_XML10_CDATA,                         is_XML_CDATA)
XML_FUNC_ALIAS(is_XML10_CHARREF_END1,                  is_XML_CHARREF_END1)
XML_FUNC_ALIAS(is_XML10_CHARREF_END2,                  is_XML_CHARREF_END2)
XML_FUNC_ALIAS(is_XML10_CHARREF_START1,                is_XML_CHARREF_START1)
XML_FUNC_ALIAS(is_XML10_CHARREF_START2,                is_XML_CHARREF_START2)
XML_FUNC_ALIAS(is_XML10_CHOICE_END,                    is_XML_CHOICE_END)
XML_FUNC_ALIAS(is_XML10_CHOICE_START,                  is_XML_CHOICE_START)
XML_FUNC_ALIAS(is_XML10_COLON,                         is_XML_COLON)
XML_FUNC_ALIAS(is_XML10_COMMA,                         is_XML_COMMA)
XML_FUNC_ALIAS(is_XML10_DOCTYPE_END,                   is_XML_DOCTYPE_END)
XML_FUNC_ALIAS(is_XML10_DOCTYPE_START,                 is_XML_DOCTYPE_START)
XML_FUNC_ALIAS(is_XML10_ELEMENTDECL_END,               is_XML_ELEMENTDECL_END)
XML_FUNC_ALIAS(is_XML10_ELEMENTDECL_START,             is_XML_ELEMENTDECL_START)
XML_FUNC_ALIAS(is_XML10_ELEMENT_END,                   is_XML_ELEMENT_END)
XML_FUNC_ALIAS(is_XML10_ELEMENT_START,                 is_XML_ELEMENT_START)
XML_FUNC_ALIAS(is_XML10_EMPTY,                         is_XML_EMPTY)
XML_FUNC_ALIAS(is_XML10_EMPTYELEM_END,                 is_XML_EMPTYELEM_END)
XML_FUNC_ALIAS(is_XML10_ENCODING,                      is_XML_ENCODING)
XML_FUNC_ALIAS(is_XML10_ENTITIES,                      is_XML_ENTITIES)
XML_FUNC_ALIAS(is_XML10_ENTITY,                        is_XML_ENTITY)
XML_FUNC_ALIAS(is_XML10_ENTITYREF_END,                 is_XML_ENTITYREF_END)
XML_FUNC_ALIAS(is_XML10_ENTITYREF_START,               is_XML_ENTITYREF_START)
XML_FUNC_ALIAS(is_XML10_ENTITY_END,                    is_XML_ENTITY_END)
XML_FUNC_ALIAS(is_XML10_ENTITY_START,                  is_XML_ENTITY_START)
XML_FUNC_ALIAS(is_XML10_ENUMERATION_END,               is_XML_ENUMERATION_END)
XML_FUNC_ALIAS(is_XML10_ENUMERATION_START,             is_XML_ENUMERATION_START)
XML_FUNC_ALIAS(is_XML10_ETAG_END,                      is_XML_ETAG_END)
XML_FUNC_ALIAS(is_XML10_ETAG_START,                    is_XML_ETAG_START)
XML_FUNC_ALIAS(is_XML10_FIXED,                         is_XML_FIXED)
XML_FUNC_ALIAS(is_XML10_ID,                            is_XML_ID)
XML_FUNC_ALIAS(is_XML10_IDREF,                         is_XML_IDREF)
XML_FUNC_ALIAS(is_XML10_IDREFS,                        is_XML_IDREFS)
XML_FUNC_ALIAS(is_XML10_IGNORE,                        is_XML_IGNORE)
XML_FUNC_ALIAS(is_XML10_IGNORESECTCONTENTSUNIT_END,    is_XML_IGNORESECTCONTENTSUNIT_END)
XML_FUNC_ALIAS(is_XML10_IGNORESECTCONTENTSUNIT_START,  is_XML_IGNORESECTCONTENTSUNIT_START)
XML_FUNC_ALIAS(is_XML10_IGNORESECT_END,                is_XML_IGNORESECT_END)
XML_FUNC_ALIAS(is_XML10_IGNORESECT_START,              is_XML_IGNORESECT_START)
XML_FUNC_ALIAS(is_XML10_IMPLIED,                       is_XML_IMPLIED)
XML_FUNC_ALIAS(is_XML10_INCLUDE,                       is_XML_INCLUDE)
XML_FUNC_ALIAS(is_XML10_INCLUDESECT_END,               is_XML_INCLUDESECT_END)
XML_FUNC_ALIAS(is_XML10_INCLUDESECT_START,             is_XML_INCLUDESECT_START)
XML_FUNC_ALIAS(is_XML10_LBRACKET,                      is_XML_LBRACKET)
XML_FUNC_ALIAS(is_XML10_MIXED_END1,                    is_XML_MIXED_END1)
XML_FUNC_ALIAS(is_XML10_MIXED_END2,                    is_XML_MIXED_END2)
XML_FUNC_ALIAS(is_XML10_MIXED_START,                   is_XML_MIXED_START)
XML_FUNC_ALIAS(is_XML10_NDATA,                         is_XML_NDATA)
XML_FUNC_ALIAS(is_XML10_NMTOKEN,                       is_XML_NMTOKEN)
XML_FUNC_ALIAS(is_XML10_NMTOKENS,                      is_XML_NMTOKENS)
XML_FUNC_ALIAS(is_XML10_NO,                            is_XML_NO)
XML_FUNC_ALIAS(is_XML10_NOTATION,                      is_XML_NOTATION)
XML_FUNC_ALIAS(is_XML10_NOTATIONDECL_END,              is_XML_NOTATIONDECL_END)
XML_FUNC_ALIAS(is_XML10_NOTATIONDECL_START,            is_XML_NOTATIONDECL_START)
XML_FUNC_ALIAS(is_XML10_NOTATION_END,                  is_XML_NOTATION_END)
XML_FUNC_ALIAS(is_XML10_NOTATION_START,                is_XML_NOTATION_START)
XML_FUNC_ALIAS(is_XML10_OR,                            is_XML_OR)
XML_FUNC_ALIAS(is_XML10_PCDATA,                        is_XML_PCDATA)
XML_FUNC_ALIAS(is_XML10_PERCENT,                       is_XML_PERCENT)
XML_FUNC_ALIAS(is_XML10_PEREFERENCE_END,               is_XML_PEREFERENCE_END)
XML_FUNC_ALIAS(is_XML10_PEREFERENCE_START,             is_XML_PEREFERENCE_START)
XML_FUNC_ALIAS(is_XML10_PLUS,                          is_XML_PLUS)
XML_FUNC_ALIAS(is_XML10_PUBLIC,                        is_XML_PUBLIC)
XML_FUNC_ALIAS(is_XML10_QUESTIONMARK,                  is_XML_QUESTIONMARK)
XML_FUNC_ALIAS(is_XML10_RBRACKET,                      is_XML_RBRACKET)
XML_FUNC_ALIAS(is_XML10_REQUIRED,                      is_XML_REQUIRED)
XML_FUNC_ALIAS(is_XML10_SEQ_END,                       is_XML_SEQ_END)
XML_FUNC_ALIAS(is_XML10_SEQ_START,                     is_XML_SEQ_START)
XML_FUNC_ALIAS(is_XML10_STANDALONE,                    is_XML_STANDALONE)
XML_FUNC_ALIAS(is_XML10_STAR,                          is_XML_STAR)
XML_FUNC_ALIAS(is_XML10_SYSTEM,                        is_XML_SYSTEM)
XML_FUNC_ALIAS(is_XML10_TEXTDECL_END,                  is_XML_TEXTDECL_END)
XML_FUNC_ALIAS(is_XML10_TEXTDECL_START,                is_XML_TEXTDECL_START)
XML_FUNC_ALIAS(is_XML10_YES,                           is_XML_YES)

/* ======================================================================= */
/*                                 XML 1.1                                 */
/*           These symbols map to a method common between 1.0 and 1.1      */
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
XML_FUNC_ALIAS(is_XML11_PUBIDCHARDQUOTEMANY,           is_XML_PUBIDCHARDQUOTEMANY)
XML_FUNC_ALIAS(is_XML11_PUBIDCHARSQUOTEMANY,           is_XML_PUBIDCHARSQUOTEMANY)
XML_FUNC_ALIAS(is_XML11_SPACE,                         is_XML_SPACE)
XML_FUNC_ALIAS(is_XML11_DQUOTE,                        is_XML_DQUOTE)
XML_FUNC_ALIAS(is_XML11_SQUOTE,                        is_XML_SQUOTE)
XML_FUNC_ALIAS(is_XML11_COMMENT_START,                 is_XML_COMMENT_START)
XML_FUNC_ALIAS(is_XML11_COMMENT_END,                   is_XML_COMMENT_END)
XML_FUNC_ALIAS(is_XML11_PI_START,                      is_XML_PI_START)
XML_FUNC_ALIAS(is_XML11_PI_END,                        is_XML_PI_END)
XML_FUNC_ALIAS(is_XML11_CDATA_START,                   is_XML_CDATA_START)
XML_FUNC_ALIAS(is_XML11_CDATA_END,                     is_XML_CDATA_END)
XML_FUNC_ALIAS(is_XML11_XMLDECL_START,                 is_XML_XMLDECL_START)
XML_FUNC_ALIAS(is_XML11_XMLDECL_END,                   is_XML_XMLDECL_END)
XML_FUNC_ALIAS(is_XML11_VERSION,                       is_XML_VERSION)
XML_FUNC_ALIAS(is_XML11_EQUAL,                         is_XML_EQUAL)
XML_FUNC_ALIAS(is_XML11_ANY,                           is_XML_ANY)
XML_FUNC_ALIAS(is_XML11_ATTLIST_END,                   is_XML_ATTLIST_END)
XML_FUNC_ALIAS(is_XML11_ATTLIST_START,                 is_XML_ATTLIST_START)
XML_FUNC_ALIAS(is_XML11_CDATA,                         is_XML_CDATA)
XML_FUNC_ALIAS(is_XML11_CHARREF_END1,                  is_XML_CHARREF_END1)
XML_FUNC_ALIAS(is_XML11_CHARREF_END2,                  is_XML_CHARREF_END2)
XML_FUNC_ALIAS(is_XML11_CHARREF_START1,                is_XML_CHARREF_START1)
XML_FUNC_ALIAS(is_XML11_CHARREF_START2,                is_XML_CHARREF_START2)
XML_FUNC_ALIAS(is_XML11_CHOICE_END,                    is_XML_CHOICE_END)
XML_FUNC_ALIAS(is_XML11_CHOICE_START,                  is_XML_CHOICE_START)
XML_FUNC_ALIAS(is_XML11_COLON,                         is_XML_COLON)
XML_FUNC_ALIAS(is_XML11_COMMA,                         is_XML_COMMA)
XML_FUNC_ALIAS(is_XML11_DOCTYPE_END,                   is_XML_DOCTYPE_END)
XML_FUNC_ALIAS(is_XML11_DOCTYPE_START,                 is_XML_DOCTYPE_START)
XML_FUNC_ALIAS(is_XML11_ELEMENTDECL_END,               is_XML_ELEMENTDECL_END)
XML_FUNC_ALIAS(is_XML11_ELEMENTDECL_START,             is_XML_ELEMENTDECL_START)
XML_FUNC_ALIAS(is_XML11_ELEMENT_END,                   is_XML_ELEMENT_END)
XML_FUNC_ALIAS(is_XML11_ELEMENT_START,                 is_XML_ELEMENT_START)
XML_FUNC_ALIAS(is_XML11_EMPTY,                         is_XML_EMPTY)
XML_FUNC_ALIAS(is_XML11_EMPTYELEM_END,                 is_XML_EMPTYELEM_END)
XML_FUNC_ALIAS(is_XML11_ENCODING,                      is_XML_ENCODING)
XML_FUNC_ALIAS(is_XML11_ENTITIES,                      is_XML_ENTITIES)
XML_FUNC_ALIAS(is_XML11_ENTITY,                        is_XML_ENTITY)
XML_FUNC_ALIAS(is_XML11_ENTITYREF_END,                 is_XML_ENTITYREF_END)
XML_FUNC_ALIAS(is_XML11_ENTITYREF_START,               is_XML_ENTITYREF_START)
XML_FUNC_ALIAS(is_XML11_ENTITY_END,                    is_XML_ENTITY_END)
XML_FUNC_ALIAS(is_XML11_ENTITY_START,                  is_XML_ENTITY_START)
XML_FUNC_ALIAS(is_XML11_ENUMERATION_END,               is_XML_ENUMERATION_END)
XML_FUNC_ALIAS(is_XML11_ENUMERATION_START,             is_XML_ENUMERATION_START)
XML_FUNC_ALIAS(is_XML11_ETAG_END,                      is_XML_ETAG_END)
XML_FUNC_ALIAS(is_XML11_ETAG_START,                    is_XML_ETAG_START)
XML_FUNC_ALIAS(is_XML11_FIXED,                         is_XML_FIXED)
XML_FUNC_ALIAS(is_XML11_ID,                            is_XML_ID)
XML_FUNC_ALIAS(is_XML11_IDREF,                         is_XML_IDREF)
XML_FUNC_ALIAS(is_XML11_IDREFS,                        is_XML_IDREFS)
XML_FUNC_ALIAS(is_XML11_IGNORE,                        is_XML_IGNORE)
XML_FUNC_ALIAS(is_XML11_IGNORESECTCONTENTSUNIT_END,    is_XML_IGNORESECTCONTENTSUNIT_END)
XML_FUNC_ALIAS(is_XML11_IGNORESECTCONTENTSUNIT_START,  is_XML_IGNORESECTCONTENTSUNIT_START)
XML_FUNC_ALIAS(is_XML11_IGNORESECT_END,                is_XML_IGNORESECT_END)
XML_FUNC_ALIAS(is_XML11_IGNORESECT_START,              is_XML_IGNORESECT_START)
XML_FUNC_ALIAS(is_XML11_IMPLIED,                       is_XML_IMPLIED)
XML_FUNC_ALIAS(is_XML11_INCLUDE,                       is_XML_INCLUDE)
XML_FUNC_ALIAS(is_XML11_INCLUDESECT_END,               is_XML_INCLUDESECT_END)
XML_FUNC_ALIAS(is_XML11_INCLUDESECT_START,             is_XML_INCLUDESECT_START)
XML_FUNC_ALIAS(is_XML11_LBRACKET,                      is_XML_LBRACKET)
XML_FUNC_ALIAS(is_XML11_MIXED_END1,                    is_XML_MIXED_END1)
XML_FUNC_ALIAS(is_XML11_MIXED_END2,                    is_XML_MIXED_END2)
XML_FUNC_ALIAS(is_XML11_MIXED_START,                   is_XML_MIXED_START)
XML_FUNC_ALIAS(is_XML11_NDATA,                         is_XML_NDATA)
XML_FUNC_ALIAS(is_XML11_NMTOKEN,                       is_XML_NMTOKEN)
XML_FUNC_ALIAS(is_XML11_NMTOKENS,                      is_XML_NMTOKENS)
XML_FUNC_ALIAS(is_XML11_NO,                            is_XML_NO)
XML_FUNC_ALIAS(is_XML11_NOTATION,                      is_XML_NOTATION)
XML_FUNC_ALIAS(is_XML11_NOTATIONDECL_END,              is_XML_NOTATIONDECL_END)
XML_FUNC_ALIAS(is_XML11_NOTATIONDECL_START,            is_XML_NOTATIONDECL_START)
XML_FUNC_ALIAS(is_XML11_NOTATION_END,                  is_XML_NOTATION_END)
XML_FUNC_ALIAS(is_XML11_NOTATION_START,                is_XML_NOTATION_START)
XML_FUNC_ALIAS(is_XML11_OR,                            is_XML_OR)
XML_FUNC_ALIAS(is_XML11_PCDATA,                        is_XML_PCDATA)
XML_FUNC_ALIAS(is_XML11_PERCENT,                       is_XML_PERCENT)
XML_FUNC_ALIAS(is_XML11_PEREFERENCE_END,               is_XML_PEREFERENCE_END)
XML_FUNC_ALIAS(is_XML11_PEREFERENCE_START,             is_XML_PEREFERENCE_START)
XML_FUNC_ALIAS(is_XML11_PLUS,                          is_XML_PLUS)
XML_FUNC_ALIAS(is_XML11_PUBLIC,                        is_XML_PUBLIC)
XML_FUNC_ALIAS(is_XML11_QUESTIONMARK,                  is_XML_QUESTIONMARK)
XML_FUNC_ALIAS(is_XML11_RBRACKET,                      is_XML_RBRACKET)
XML_FUNC_ALIAS(is_XML11_REQUIRED,                      is_XML_REQUIRED)
XML_FUNC_ALIAS(is_XML11_SEQ_END,                       is_XML_SEQ_END)
XML_FUNC_ALIAS(is_XML11_SEQ_START,                     is_XML_SEQ_START)
XML_FUNC_ALIAS(is_XML11_STANDALONE,                    is_XML_STANDALONE)
XML_FUNC_ALIAS(is_XML11_STAR,                          is_XML_STAR)
XML_FUNC_ALIAS(is_XML11_SYSTEM,                        is_XML_SYSTEM)
XML_FUNC_ALIAS(is_XML11_TEXTDECL_END,                  is_XML_TEXTDECL_END)
XML_FUNC_ALIAS(is_XML11_TEXTDECL_START,                is_XML_TEXTDECL_START)
XML_FUNC_ALIAS(is_XML11_YES,                           is_XML_YES)

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

STRLEN
is_XML10_PUBIDCHARDQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PUBIDCHARDQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PUBIDCHARDQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PUBIDCHARDQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PUBIDCHARSQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PUBIDCHARSQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PUBIDCHARSQUOTEMANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PUBIDCHARSQUOTEMANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_SPACE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_SPACE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_SPACE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_SPACE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_DQUOTE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_DQUOTE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_DQUOTE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_DQUOTE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_SQUOTE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_SQUOTE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_SQUOTE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_SQUOTE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_COMMENT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_COMMENT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_COMMENT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_COMMENT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_COMMENT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_COMMENT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_COMMENT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_COMMENT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PI_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PI_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PI_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PI_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PI_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PI_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PI_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PI_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CDATA_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CDATA_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CDATA_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CDATA_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CDATA_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CDATA_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CDATA_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CDATA_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_XMLDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_XMLDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_XMLDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_XMLDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_XMLDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_XMLDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_XMLDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_XMLDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_VERSION(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_VERSION(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_VERSION(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_VERSION(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_EQUAL(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_EQUAL(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_EQUAL(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_EQUAL(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_VERSIONNUM(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_VERSIONNUM(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_VERSIONNUM(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_VERSIONNUM(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ANY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ANY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ATTLIST_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ATTLIST_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ATTLIST_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ATTLIST_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ATTLIST_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ATTLIST_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ATTLIST_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ATTLIST_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHARREF_END1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHARREF_END1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHARREF_END1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHARREF_END1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHARREF_END2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHARREF_END2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHARREF_END2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHARREF_END2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHARREF_START1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHARREF_START1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHARREF_START1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHARREF_START1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHARREF_START2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHARREF_START2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHARREF_START2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHARREF_START2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHOICE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHOICE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHOICE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHOICE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_CHOICE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_CHOICE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_CHOICE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_CHOICE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_COLON(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_COLON(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_COLON(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_COLON(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_COMMA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_COMMA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_COMMA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_COMMA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_DOCTYPE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_DOCTYPE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_DOCTYPE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_DOCTYPE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_DOCTYPE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_DOCTYPE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_DOCTYPE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_DOCTYPE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ELEMENTDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ELEMENTDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ELEMENTDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ELEMENTDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ELEMENTDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ELEMENTDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ELEMENTDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ELEMENTDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ELEMENT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ELEMENT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ELEMENT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ELEMENT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ELEMENT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ELEMENT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ELEMENT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ELEMENT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_EMPTY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_EMPTY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_EMPTY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_EMPTY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_EMPTYELEM_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_EMPTYELEM_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_EMPTYELEM_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_EMPTYELEM_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENCODING(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENCODING(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENCODING(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENCODING(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITIES(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITIES(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITIES(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITIES(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITY(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITY(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITYREF_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITYREF_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITYREF_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITYREF_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITYREF_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITYREF_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITYREF_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITYREF_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITY_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITY_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITY_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITY_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENTITY_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENTITY_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENTITY_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENTITY_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENUMERATION_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENUMERATION_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENUMERATION_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENUMERATION_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ENUMERATION_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ENUMERATION_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ENUMERATION_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ENUMERATION_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ETAG_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ETAG_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ETAG_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ETAG_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ETAG_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ETAG_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ETAG_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ETAG_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_FIXED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_FIXED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_FIXED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_FIXED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_ID(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_ID(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_ID(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_ID(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IDREF(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IDREF(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IDREF(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IDREF(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IDREFS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IDREFS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IDREFS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IDREFS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNORE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNORE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNORE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNORE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNORESECTCONTENTSUNIT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNORESECTCONTENTSUNIT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNORESECTCONTENTSUNIT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNORESECTCONTENTSUNIT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNORESECTCONTENTSUNIT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNORESECTCONTENTSUNIT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNORESECTCONTENTSUNIT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNORESECTCONTENTSUNIT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNORESECT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNORESECT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNORESECT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNORESECT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IGNORESECT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IGNORESECT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IGNORESECT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IGNORESECT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_IMPLIED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_IMPLIED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_IMPLIED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_IMPLIED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_INCLUDE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_INCLUDE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_INCLUDE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_INCLUDE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_INCLUDESECT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_INCLUDESECT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_INCLUDESECT_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_INCLUDESECT_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_INCLUDESECT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_INCLUDESECT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_INCLUDESECT_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_INCLUDESECT_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_LBRACKET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_LBRACKET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_LBRACKET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_LBRACKET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_MIXED_END1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_MIXED_END1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_MIXED_END1(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_MIXED_END1(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_MIXED_END2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_MIXED_END2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_MIXED_END2(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_MIXED_END2(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_MIXED_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_MIXED_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_MIXED_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_MIXED_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NMTOKEN(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NMTOKEN(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NMTOKEN(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NMTOKEN(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NMTOKENS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NMTOKENS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NMTOKENS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NMTOKENS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NO(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NO(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NO(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NO(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOTATION(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOTATION(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOTATION(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOTATION(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOTATIONDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOTATIONDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOTATIONDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOTATIONDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOTATIONDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOTATIONDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOTATIONDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOTATIONDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOTATION_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOTATION_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOTATION_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOTATION_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_NOTATION_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_NOTATION_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_NOTATION_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_NOTATION_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_OR(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_OR(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_OR(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_OR(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PCDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PCDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PCDATA(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PCDATA(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PERCENT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PERCENT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PERCENT(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PERCENT(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PEREFERENCE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PEREFERENCE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PEREFERENCE_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PEREFERENCE_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PEREFERENCE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PEREFERENCE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PEREFERENCE_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PEREFERENCE_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PLUS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PLUS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PLUS(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PLUS(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_PUBLIC(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_PUBLIC(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_PUBLIC(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_PUBLIC(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_QUESTIONMARK(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_QUESTIONMARK(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_QUESTIONMARK(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_QUESTIONMARK(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_RBRACKET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_RBRACKET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_RBRACKET(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_RBRACKET(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_REQUIRED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_REQUIRED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_REQUIRED(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_REQUIRED(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_SEQ_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_SEQ_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_SEQ_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_SEQ_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_SEQ_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_SEQ_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_SEQ_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_SEQ_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_STANDALONE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_STANDALONE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_STANDALONE(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_STANDALONE(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_STAR(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_STAR(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_STAR(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_STAR(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_SYSTEM(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_SYSTEM(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_SYSTEM(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_SYSTEM(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_TEXTDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_TEXTDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_TEXTDECL_END(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_TEXTDECL_END(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_TEXTDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_TEXTDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_TEXTDECL_START(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_TEXTDECL_START(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML10_YES(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML10_YES(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL

STRLEN
is_XML11_YES(sv, pos)
    SV *sv
    STRLEN pos
  CODE:
  RETVAL = is_XML11_YES(aTHX_ sv, pos, NULL, NULL);
  OUTPUT:
    RETVAL
