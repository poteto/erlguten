%%==========================================================================
%% Copyright (C) 2003 Mikael Karlsson
%%
%% Permission is hereby granted, free of charge, to any person obtaining a
%% copy of this software and associated documentation files (the
%% "Software"), to deal in the Software without restriction, including
%% without limitation the rights to use, copy, modify, merge, publish,
%% distribute, sublicense, and/or sell copies of the Software, and to permit
%% persons to whom the Software is furnished to do so, subject to the
%% following conditions:
%% 
%% The above copyright notice and this permission notice shall be included
%% in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
%% OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
%% NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
%% DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
%% OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
%% USE OR OTHER DEALINGS IN THE SOFTWARE.
%%
%% Author:   Mikael Karlsson <mikael.karlsson@creado.com>
%%           Carl Wright <wright@servicelevel.net>
%% Purpose: Import images to PDF
%%==========================================================================

-module(eg_pdf_image).

%% Purpose: Import images from file, currently jpg only 
%%          Pack into XObjects
%% 

-export([mk_images/4, 
        get_head_info/1, 
        process_header/1, 
        get_png_content/1,
        deflate_stream/1,
        inflate_stream/1]).

-include("../include/eg.hrl").

%% ============================================================================

%% @spec mk_images(Images, Count, [], []) -> {Free, XObjects, O0s}
%% @doc mk_images takes a list of images and turns them into PDF XObjects
%% to go into the PDF document. 

mk_images([], I, Is, Os) -> 
    A = {{obj,I,0},{dict,lists:map(fun({Alias, ImageIndex}) ->
					   {Alias, {ptr,ImageIndex,0}}
				   end, 
				   lists:reverse(Is))}},
    {I+1, {ptr,I,0}, lists:reverse([A|Os])};
mk_images([{ImageURI, #image{alias=Alias}=Im}|T], I, Fs, E) ->
  List = case mk_image(I, ImageURI, Im) of
    {J, [A,[]]} ->
      [A|E] ;
    {J, [A,B]} ->
      [A,B|E]  
  end,
  mk_images(T, J+1, [{Alias,I}|Fs], List).
 
mk_image(I, File, #image{alias=_Alias, width=W, height=H}) ->
    Image = read_image(File),
    case process_header(Image) of
	{jpeg_head,{Width, Height, Ncomponents, Data_precision}} ->
	    Extras = [{"Filter", {name,"DCTDecode"}},
		      {"ColorSpace",{name, colorspace(Ncomponents)}},
		      {"BitsPerComponent", Data_precision}],
		      Image2 = Image,
		      J = I,
		      ExtraObj = [];
	{png_head,{Width, Height, Ncomponents, Data_precision}} ->
	  [_Params, MoreParams, Palette, Image2 , Alpha_channel] = get_png_content(File),
	  case Ncomponents of 
	    0 ->
	    Extras = [{"Filter", {name,"FlateDecode"}},
	        {"DecodeParms", {dict,[{"Predictor", 15}, 
	                              {"Colors", pngbits(Ncomponents)},
	                              {"BitsPerComponent", Data_precision},
	                              {"Columns", Width}] } },
		      {"ColorSpace",{name, pngcolor(Ncomponents)}},
		      {"BitsPerComponent", Data_precision}],
		      J = I,
		      ExtraObj = [];
	    2 ->
	    Extras = [{"Filter", {name,"FlateDecode"}},
	        {"BitsPerComponent", Data_precision},
	        {"DecodeParms", {dict,[{"Predictor", 15}, 
	                              {"Colors", pngbits(Ncomponents)},
	                              {"BitsPerComponent", Data_precision},
	                              {"Columns", Width}] } },
		      {"ColorSpace",{name, pngcolor(Ncomponents)}}],
		      J = I,
		      ExtraObj = [];
	    3 ->
	    		J = I + 1,
	    		Extras = [{"Filter", {name,"FlateDecode"}},
	    		{"BitsPerComponent", Data_precision},
	        {"DecodeParms", {dict,[{"Predictor", 15}, 
	                              {"Colors", pngbits(Ncomponents)},
	                              {"BitsPerComponent", Data_precision},
	                              {"Columns", Width}] } },
		      {"ColorSpace",{array,[{name,"Indexed"},{name,"DeviceRGB"}, 
		                    round(((length(binary_to_list(Palette))/3)-1)), {ptr, J, 0}] }}],

		      ExtraObj = {{obj,J, 0}, {stream, Palette}};

	    4 ->
		      J = I + 1,
	        Extras = [{"Filter", {name,"FlateDecode"}},
	        {"BitsPerComponent", Data_precision},
		      {"ColorSpace",{name, pngcolor(Ncomponents)}},
		      {"Smask", {ptr, J, 0}}],
		     

		      ExtraObj = {{obj,J, 0}, {stream, 
		            {dict,[{"Type",{name,"XObject"}},
            	     {"Subtype",{name,"Image"}},
            	     {"Width",Width},
            	     {"Height", Height},
            	     {"BitsPerComponent", Data_precision},
            	     {"Filter", {name,"FlateDecode"}},
            	     {"ColorSpace",{name, pngcolor(Ncomponents)}},
            	     {"Decode",{array,[0,1]}}]},
          	     Alpha_channel}};
	    6 ->
		      J = I + 1,
	        Extras = [{"Filter", {name,"FlateDecode"}},
	        {"BitsPerComponent", Data_precision},
		      {"ColorSpace",{name, pngcolor(Ncomponents)}},
		      {"Smask", {ptr, J, 0}}],
		     

		      ExtraObj = {{obj,J, 0}, {stream, 
		            {dict,[{"Type",{name,"XObject"}},
            	     {"Subtype",{name,"Image"}},
            	     {"Width",Width},
            	     {"Height", Height},
            	     {"BitsPerComponent", Data_precision},
            	     {"Filter", {name,"FlateDecode"}},
            	     {"ColorSpace",{name, "DeviceGray"}},
            	     {"Decode",{array,[0,1]}}]},
          	     Alpha_channel}}
      end;
	_ ->
	    {Width, Height} = {W,H},
	    Image2 = Image,
	    Extras = [],
	    J = I,
	    ExtraObj = []
    end,
   {J, [{{obj,I,0}, 
     {stream,	  
      {dict,[{"Type",{name,"XObject"}},
	     {"Subtype",{name,"Image"}},
	     {"Width",Width},
	     {"Height", Height}| Extras ]},
      Image2}
    },ExtraObj]}.


colorspace(0)-> "DeviceGray";
colorspace(1)-> "DeviceGray";
colorspace(2)-> "DeviceGray";
colorspace(3)-> "DeviceRGB";
colorspace(4)-> "DeviceCMYK".

pngcolor(X) ->
  {A,_} = pngspace(X),
  A.
pngbits(X) ->
  {_, B} = pngspace(X),
  B.
pngspace(0)-> {"DeviceGray", 1};
pngspace(2)-> {"DeviceRGB", 3};
pngspace(3)-> {"DeviceGray", 1};
pngspace(4)-> {"DeviceGray", 1};
pngspace(6)-> {"DeviceRGB", 3}.

read_image(File) ->
  case file:read_file(File) of
    {ok, Image} ->
      Image;
    {error, Reason} ->
      io:format("Can not read file ~s; reason is ~s~n",[File,Reason]),
      error 
  end.

%% @spec get_head_info(Filepath) -> {jpeg_head,{Width, Height, Number_of_components, Precision}}
%% Filepath = string()
%% Width = integer()
%% Height = integer()
%% Number_of_components = integer()
%% Precision = integer()
%% @doc When called with a file path string, this returns a tuple of info
%% on the jpeg at the file path location. The tuple is like the following <br/>
%% <center>{ jpeg_head, { Width(pixels), Height(pixels), 
%% Number_of_color_components(1, 3, 4), Data_precision(bits size)}} </center>

get_head_info(File) ->
    process_header(read_image(File)).

%% JPEG support
-define(SOF0,  16#C0).     %% Start Of Frame
-define(SOF1,  16#C1).     %% Digit indicates compression type
-define(SOF2,  16#C2).     %% Only SOF0-SOF2 are now in common use
-define(SOF3,  16#C3).
-define(SOF5,  16#C5).
-define(SOF6,  16#C6).
-define(SOF7,  16#C7).
-define(SOF9,  16#C9).
-define(SOF10, 16#CA).
-define(SOF11, 16#CB).
-define(SOF13, 16#CD).
-define(SOF14, 16#CE).
-define(SOF15, 16#CF).
-define(SOI,   16#D8).     %% Start Of Image (beginning of file) 
-define(EOI,   16#D9).     %% End Of Image 
-define(SOS,   16#DA).     %% Start Of Scan (begin of compressed data) 
%% -define(APP0,  16#E0).  %% Application-specific markers, don't bother
%% -define(APP12, 16#EC).     
%% -define(COM,   16#FE).  %% Comment 



%% @spec process_header(Jpeg) -> {jpeg_head,{Width, Height, Number_of_components, Precision}}
%% Jpeg = binary()
%% Width = integer()
%% Height = integer()
%% Number_of_components = integer()
%% Precision = integer()
%% @doc Same as get_head_info except it is called with a binary that holds the 
%% content of a JPG file. This returns a tuple of info
%% on the jpeg. The tuple is like the following <br/>
%% <center>{ jpeg_head, { Width(pixels), Height(pixels), 
%% Number_of_color_components(1, 3, 4), Data_precision(bits size)}} </center>



process_header( << 16#FF:8, ?SOI:8, Rest/binary >> )->
    process_jpeg( Rest );
process_header( << 137:8, 80:8, 78:8, 71:8, 13:8, 10:8, 26:8, 10:8, Rest/binary >> )->
    [Params, _MoreParams, _Palette, _Image , _Alpha_channel] = png_head( Rest,[],[], [], [], [] ),
    Params;
process_header(_Any) ->
    image_format_not_yet_implemented_or_unknown.


%% @doc JPEG file header processing
%% it skips over characters until it gets a character that marks 
%% the beginning of the bytes that define the shape of the image data

%% Skip any leading 16#FF
process_jpeg( << 16#FF:8,Rest/binary >> ) -> process_jpeg(Rest);

%% Codes 0xC4, 0xC8, 0xCC shall not be treated as SOFn.
process_jpeg( << ?SOF0:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF1:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF2:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF3:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF5:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF6:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF7:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF9:8,Rest/binary >> ) -> jpeg_sof( Rest);
process_jpeg( << ?SOF10:8,Rest/binary >> ) -> jpeg_sof(Rest);
process_jpeg( << ?SOF11:8,Rest/binary >> ) -> jpeg_sof(Rest);
process_jpeg( << ?SOF13:8,Rest/binary >> ) -> jpeg_sof(Rest);
process_jpeg( << ?SOF14:8,Rest/binary >> ) -> jpeg_sof(Rest);
process_jpeg( << ?SOF15:8,Rest/binary >> ) -> jpeg_sof(Rest);
process_jpeg( << ?SOS:8,_Rest/binary >> ) ->[];
process_jpeg( << ?EOI:8,_Rest/binary >> ) -> jeoi; %% Tables only
process_jpeg( << _Any:8, Rest/binary >> )->process_jpeg(skip_marker(Rest));
process_jpeg( << >> ) -> [].

jpeg_sof ( Rest )->
    << _Length:16, Data_precision:8, Height:16, Width:16, 
    Ncomponents:8, _Rest2/binary >> = Rest, 
    {jpeg_head,{Width, Height, Ncomponents, Data_precision}}.


skip_marker(Image)->
    << Length:16, Rest/binary >> = Image, 
    AdjLen = Length-2,
    << _Skip:AdjLen/binary, Rest2/binary >> = Rest,
    Rest2.

png_head( <<_Length:32, $I:8, $H:8, $D:8, $R:8, 
              Width:32/integer, Height:32/integer, Data_precision:8/integer, 
              Color_type:8/integer, Compression:8/integer, Filter_method:8/integer,
              Interface_method:8/integer, _CRC:32, _Rest/binary >>, 
              _Params, _MoreParams, Palette, Image, Alpha_channel) ->
                    [{png_head,{Width, Height, Color_type, Data_precision}},
                    {params, Compression, Filter_method, Interface_method}, 
                    Palette, Image, Alpha_channel].
                  
get_png_content(File) ->
  case file:read_file(File) of
    {ok, Image} ->
      process_png_header( Image );
    {error, Reason} ->
      io:format("Can not read file ~s; reason is ~s~n",[File,Reason]),
      error 
  end.                     

process_png_header( << 137:8, 80:8, 78:8, 71:8, 13:8, 10:8, 26:8, 10:8, Rest/binary >> )->
        process_png(Rest, [], [], [], [], []).
                        
process_png( <<_Length:32, $I:8, $H:8, $D:8, $R:8, 
              Width:32/integer, Height:32/integer, Data_precision:8/integer, 
              Color_type:8/integer, Compression:8/integer, Filter_method:8/integer,
              Interface_method:8/integer, _CRC:32, Rest/binary >>, 
              _Params, _MoreParams, Palette, Image, Alpha_channel) ->
        process_png( Rest,{png_head,{Width, Height, Color_type, Data_precision}},
                {params, Compression, Filter_method, Interface_method, undefined}, Palette, Image, Alpha_channel);
        
process_png( <<Length:32, $P:8, $L:8, $T:8, $E:8,  Data:Length/binary-unit:8, _CRC:32, Rest/binary >>, 
              Params, MoreParams, Palette, Image, Alpha_channel) ->
                io:format("Palette length = ~w~n",[Length]),
        process_png( Rest, Params, MoreParams, Palette ++ binary_to_list(Data), Image, Alpha_channel);
        
process_png( <<Length:32, $I:8, $D:8, $A:8, $T:8,  Data:Length/binary-unit:8, _CRC:32, Rest/binary >>, 
              Params, MoreParams, Palette, Image, Alpha_channel) ->
        process_png( Rest, Params, MoreParams, Palette, Image ++ binary_to_list(Data) , Alpha_channel);

process_png( <<Length:32, $t:8, $R:8, $N:8, $S:8,  Data:Length/binary-unit:8, _CRC:32, Rest/binary >>, Params, 
              {params, Compression, Filter_method, Interface_method, 
                Transparency, Indexed_alpha, Grayval, Red, Green, Blue},
              Palette, Image, Alpha_channel) ->
        {png_head,{_Width, _Height, Color_type, _Data_precision}} = Params,
        case Color_type of
          3 ->  Transparency = indexed,
                Indexed_alpha = binary_to_list(Data);
          0 ->  << Grayval:16>> = Data,
                Transparency = grayscale;
          2 -> << Red:16, Green:16, Blue:16 >> = Data,
                Transparency = rgb
        end,
        process_png( Rest, Params, {params, Compression, Filter_method, Interface_method, 
                    Transparency, Indexed_alpha, Grayval, Red, Green, Blue}, 
                    Palette, Image , Alpha_channel);
                    
               
process_png( <<_Length:32, $I:8, $E:8, $N:8, $D:8,  _Rest/binary >>, 
              Params, MoreParams, Palette, Image, Alpha_channel) ->
        {png_head,{Width, Height, Color_type, Data_precision}} = Params,
        case Color_type of
          0 ->
              [Params, MoreParams, list_to_binary(Palette), list_to_binary(Image) , list_to_binary(Alpha_channel)];
          2 ->
              [Params, MoreParams, list_to_binary(Palette), list_to_binary(Image) , list_to_binary(Alpha_channel)];
          3 ->
              [Params, MoreParams, list_to_binary(Palette), list_to_binary(Image) , list_to_binary(Alpha_channel)];
          4 ->
              {ImageScan, AlphaCodes} = extractAlphaAndData(list_to_binary(Image)),
              [Params, MoreParams, list_to_binary(Palette), ImageScan , AlphaCodes];
          6 ->        
              {ImageScan, AlphaCodes} = extractAlphaAndData(list_to_binary(Image)),
              [Params, MoreParams, list_to_binary(Palette), ImageScan , AlphaCodes]
          end;
        
process_png( <<Length:32/integer, _ID:32, _:Length/binary-unit:8, _CRC:32, Rest/binary >>, 
              Params, MoreParams, Palette, Image, Alpha_channel) ->
        process_png( Rest, Params, MoreParams, Palette, Image , Alpha_channel).   
        
extractAlphaAndData(Image) ->
  {ok,Decompressed} = deflate_stream(Image),
  {Decompressed,<< >>}.     
 
breakout({PixelSize, AlphaSize}, Stream, Pixels, Alpha_channel) ->
  <<Pixel:PixelSize, Alpha:AlphaSize, Rest/binary>> = Stream,
  breakout({PixelSize, AlphaSize},  Rest, Pixels ++ binary_to_list(Pixel), Alpha_channel ++ binary_to_list(Alpha));
breakout(Sizes, << >>,Pixels, Alpha_channel) ->
  {list_to_binary(Pixels), list_to_binary(Alpha_channel)}.
  
%% Apply the PDF filter to the bytes of the image 
filter(X,A,B,C,D, Method) ->
  NewX = case Method of
    0 -> X;
    1 -> X - A div 256;
    2 -> X - B div 256;
    3 -> (X - floor( (A + B)/2) ) div 256;
    4 -> (X - paethPredictor(A,B,C)) div 256
  end,
  NewX.

%% calculate the specialized filter invented by Mr. Paeth
  
paethPredictor(A,B,C) ->
  P = A + B - C,
  Pa = abs(P - A),
  Pb = abs( P - B),
  Pc = abs( P - C),
  Pr = if (Pa =< Pb) and (Pa =< Pc) -> A;
    (Pb =< Pc) -> B;
    true -> C
  end,
  Pr.
        
%% @doc Decompress a bit stream using the zlib/deflate algorithm
%%        
inflate_stream(Data) ->
  Z = zlib:open(),
  ok = zlib:inflateInit(Z),
  Decompressed = zlib:inflate(Z, Data),
  ok = zlib:inflateEnd(Z),
  zlib:close(Z),
  {ok,Decompressed}.
  
%% @doc Compress a bit stream using the zlib/deflate algorithm
%% 
deflate_stream(Data) ->
  Z = zlib:open(),
  zlib:deflateInit(Z),
  B1 = zlib:deflate(Z,Data),
  B2 = zlib:deflate(Z,<< >>,finish),
  zlib:deflateEnd(Z),
  Compressed = list_to_binary([B1,B2]),
  zlib:close(Z),
  {ok,Compressed}.
  
  
floor(X) ->
    T = erlang:trunc(X),
    case (X - T) of
        Neg when Neg < 0 -> T - 1;
        Pos when Pos > 0 -> T;
        _ -> T
    end.