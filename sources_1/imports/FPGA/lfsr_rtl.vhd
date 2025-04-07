--=================================================================================================
-- Title       : LFSR
-- File        : lfsr_rtl.vhd
-- Description : Linear Feedback Shift Register with configurable width, polynomial and reset
--               polarity. It can be reset through the main reset_n signal of the PUF system, or
--               from the FSM through aux_reset_n.
--               The input seed defines the value to set the LFSR when reset_n or aux_reset_n
--               signals are triggered. Also, the input value is an std_logic_vector, while each
--               generated output value lfsr is an integer.
-- Generics    : g_width            -> Number of bits of the LFSR.
--               g_polynomial       -> Polynomial to apply at every clk pulse. Default is primitive
--                                     polynomial (maximun length) given a 5-bit LFSR.
--               g_reset_polarity   -> Active high ('1') or active low ('0') rest for both reset_n
--                                     and aux_reset_n.
-- Author      : Alberto Caravantes Arranz
-- Date        : 06/04/2025
-- Version     : 1.0
--=================================================================================================

-- Revision History:
-- Version 1.0 - Initial version

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lfsr is
    generic(
        g_width             : natural := 5;
        g_polynomial        : natural := 20;
        g_reset_polarity    : std_logic := '0'
    );
    port(
        lfsr_clk    : in  std_logic;
        aux_reset_n : in std_logic;
        reset_n     : in  std_logic;
        seed        : in  std_logic_vector(g_width - 1 downto 0);
        lfsr        : out natural
    );
end entity lfsr;

architecture rtl of lfsr is

    -- Convert integer taps into a std_logic_vector mask
    constant c_taps: std_logic_vector(g_width - 1 downto 0) := std_logic_vector(to_unsigned(g_polynomial, g_width));

    -- Register to store lfsr state
    signal reg_i: std_logic_vector(g_width - 1 downto 0);

begin

    process (lfsr_clk, reset_n)
        variable feedback : std_logic;
    begin
        if ((reset_n = g_reset_polarity) or (aux_reset_n = g_reset_polarity)) then
            reg_i <= seed;
        elsif rising_edge(lfsr_clk) then

            -- Compute XOR feedback
            feedback := '0';
            for i in 0 to g_width - 1 loop
                if (c_taps(i) = '1') then
                    feedback := feedback xor reg_i(i);
                end if;
            end loop;

            -- Shift register (shift right, insert feedback at MSB)
            reg_i <= feedback & reg_i(g_width - 1 downto 1);

        end if;
    end process;

    lfsr <= to_integer(unsigned(reg_i));

end architecture rtl;
