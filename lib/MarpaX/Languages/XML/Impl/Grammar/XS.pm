package MarpaX::Languages::XML::Impl::Grammar::XS;
require Exporter;
require DynaLoader;

@ISA = qw/DynaLoader/;
@EXPORT = qw/is_XML_S/;

bootstrap MarpaX::Languages::XML::Impl::Grammar::XS;
1;
