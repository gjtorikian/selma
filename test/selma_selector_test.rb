# frozen_string_literal: true

class SelmaSelectorTest < Minitest::Test
  def test_that_it_raise_against_invalid_css
    assert_raises(ArgumentError) do
      Selma::Selector.new(match_element: %(a[href=]))
    end
  end

  def test_that_it_raises_against_empty_css
    assert_raises(ArgumentError) do
      Selma::Selector.new(match_element: "")
    end
  end
end
