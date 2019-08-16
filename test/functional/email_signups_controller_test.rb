require 'test_helper'
require 'gds_api/test_helpers/email_alert_api'

class EmailSignupsControllerTest < ActionController::TestCase
  include FeedHelper
  include GdsApi::TestHelpers::EmailAlertApi

  view_test 'GET :new with a valid field displays the subscription form' do
    topic = create(:topic)
    get :new, params: { email_signup: { feed: atom_feed_url_for(topic) } }

    assert_response :success
    assert_select "input[name='email_signup[feed]'][value='#{atom_feed_url_for(topic)}']"
  end

  view_test 'GET :new redirects to email-alert-frontend if signup is for an organisation' do
    organisation = create(:organisation)
    get :new, params: { email_signup: { feed: atom_feed_url_for(organisation) } }

    assert_redirected_to "http://test.host/email-signup?link=#{organisation.base_path}"
  end

  view_test 'GET :new with an invalid feed shows an error message' do
    get :new, params: { email_signup: { feed: 'http://nonse-feed.atom' } }

    assert_response :success
    refute_select "input[name='email_signup[feed]']"
    assert_select "p", text: /we could not find a valid email alerts feed/
  end

  test 'POST :create with a valid email signup redirects to the signup URL' do
    topical_event = create(:topical_event)

    email_alert_api_has_subscriber_list(
      "links" => { "topical_events" => [topical_event.content_id] },
      "subscription_url" => "http://email_alert_api_signup_url",
    )

    post :create, params: { email_signup: { feed: atom_feed_url_for(topical_event) } }

    assert_response :redirect
    assert_redirected_to 'http://email_alert_api_signup_url'
  end

  view_test 'POST :create with an invalid email signup shows an error message' do
    post :create, params: { email_signup: { feed: 'http://gov.uk/invalid/feed.atom' } }

    assert_response :success
    assert_select "p", text: /we could not find a valid email alerts feed/
    assert_not_requested(stub_any_email_alert_api_call)
  end
end
